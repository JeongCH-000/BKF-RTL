"""Bit-accurate signed fixed-point arithmetic for the nominal RTL contract."""

from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Iterable

import numpy as np

from nominal_config import (
    FRACTIONAL_BITS,
    MEASUREMENT_COVARIANCE_DIAGONAL,
    PROCESS_COVARIANCE_DIAGONAL,
    SIGNED_WIDTH,
    quantize_config_value,
)


WIDTH = SIGNED_WIDTH
FRAC = FRACTIONAL_BITS
SCALE = 1 << FRAC
FX_MIN = -(1 << (WIDTH - 1))
FX_MAX = (1 << (WIDTH - 1)) - 1
ONE = SCALE
Q_DIAG = quantize_config_value(PROCESS_COVARIANCE_DIAGONAL)
R_DIAG = quantize_config_value(MEASUREMENT_COVARIANCE_DIAGONAL)
ALPHA = quantize_config_value(math.sqrt(2.0 / math.pi))
DIAG_FLOOR = 64  # 2^-10, outside the nominal path
DET_FLOOR = 64
RSQRT_ADDR_BITS = 12
RSQRT_DEPTH = 1 << RSQRT_ADDR_BITS
RSQRT_ADDR_SHIFT = FRAC - 10  # LUT spacing is 2^-10 over [0, 4)
ASIN_DEPTH = 4097
ASIN_ADDR_SHIFT = FRAC - 11  # LUT spacing is 2^-11 over [-1, 1]


@dataclass
class ArithmeticStats:
    saturation_count: int = 0
    positive_saturation_count: int = 0
    negative_saturation_count: int = 0
    correlation_clamp_count: int = 0
    diagonal_floor_count: int = 0
    determinant_floor_count: int = 0
    divide_by_zero_count: int = 0
    max_abs_product: int = 0
    max_abs_mac_accumulator: int = 0
    max_abs_dividend: int = 0

    def to_dict(self) -> dict[str, int]:
        return asdict(self)


def quantize_scalar(value: float, stats: ArithmeticStats | None = None) -> int:
    magnitude = int(math.floor(abs(float(value)) * SCALE + 0.5))
    quantized = -magnitude if value < 0 else magnitude
    return saturate(quantized, stats)


def quantize_array(value: np.ndarray) -> np.ndarray:
    vectorized = np.vectorize(lambda item: quantize_scalar(float(item)), otypes=[np.int64])
    return vectorized(np.asarray(value))


def dequantize(value: int | np.ndarray) -> float | np.ndarray:
    return np.asarray(value, dtype=np.float64) / SCALE if isinstance(value, np.ndarray) else value / SCALE


def saturate(value: int, stats: ArithmeticStats | None = None) -> int:
    value = int(value)
    if value > FX_MAX:
        if stats is not None:
            stats.saturation_count += 1
            stats.positive_saturation_count += 1
        return FX_MAX
    if value < FX_MIN:
        if stats is not None:
            stats.saturation_count += 1
            stats.negative_saturation_count += 1
        return FX_MIN
    return value


def round_shift_away(value: int, shift: int) -> int:
    """Round to nearest with exact half cases away from zero."""
    value = int(value)
    if shift == 0:
        return value
    half = 1 << (shift - 1)
    if value < 0:
        return -(((-value) + half) >> shift)
    return (value + half) >> shift


def fx_add(left: int, right: int, stats: ArithmeticStats | None = None) -> int:
    return saturate(int(left) + int(right), stats)


def fx_sub(left: int, right: int, stats: ArithmeticStats | None = None) -> int:
    return saturate(int(left) - int(right), stats)


def fx_mul(left: int, right: int, stats: ArithmeticStats | None = None) -> int:
    product = int(left) * int(right)
    if stats is not None:
        stats.max_abs_product = max(stats.max_abs_product, abs(product))
    return saturate(round_shift_away(product, FRAC), stats)


def fx_mac(products: Iterable[tuple[int, int]], stats: ArithmeticStats | None = None) -> int:
    accumulator = 0
    for left, right in products:
        product = int(left) * int(right)
        accumulator += product
        if stats is not None:
            stats.max_abs_product = max(stats.max_abs_product, abs(product))
            stats.max_abs_mac_accumulator = max(stats.max_abs_mac_accumulator, abs(accumulator))
    return saturate(round_shift_away(accumulator, FRAC), stats)


def fx_average(left: int, right: int, stats: ArithmeticStats | None = None) -> int:
    return saturate(round_shift_away(int(left) + int(right), 1), stats)


def fx_div(numerator: int, denominator: int, stats: ArithmeticStats | None = None) -> int:
    numerator = int(numerator)
    denominator = int(denominator)
    if denominator == 0:
        if stats is not None:
            stats.divide_by_zero_count += 1
        return FX_MAX if numerator >= 0 else FX_MIN
    negative = (numerator < 0) ^ (denominator < 0)
    dividend = abs(numerator) << FRAC
    divisor = abs(denominator)
    if stats is not None:
        stats.max_abs_dividend = max(stats.max_abs_dividend, dividend)
    quotient = (dividend + (divisor >> 1)) // divisor
    return saturate(-quotient if negative else quotient, stats)


def matrix_transpose(matrix: list[list[int]]) -> list[list[int]]:
    return [[int(matrix[j][i]) for j in range(3)] for i in range(3)]


def matrix_multiply(
    left: list[list[int]], right: list[list[int]], stats: ArithmeticStats | None = None
) -> list[list[int]]:
    return [
        [fx_mac(((left[i][k], right[k][j]) for k in range(3)), stats) for j in range(3)]
        for i in range(3)
    ]


def matrix_vector_multiply(
    matrix: list[list[int]], vector: list[int], stats: ArithmeticStats | None = None
) -> list[int]:
    return [fx_mac(((matrix[i][k], vector[k]) for k in range(3)), stats) for i in range(3)]


def matrix_symmetrize(matrix: list[list[int]], stats: ArithmeticStats | None = None) -> list[list[int]]:
    result = [[int(matrix[i][j]) for j in range(3)] for i in range(3)]
    for i in range(3):
        for j in range(i + 1, 3):
            average = fx_average(matrix[i][j], matrix[j][i], stats)
            result[i][j] = average
            result[j][i] = average
    return result


def matrix_inverse_3x3(
    matrix: list[list[int]], stats: ArithmeticStats | None = None
) -> tuple[list[list[int]], int, bool]:
    """Quantized adjugate/determinant inverse; returns inverse, determinant, floor flag."""
    a = matrix
    cof = [[0] * 3 for _ in range(3)]
    cof[0][0] = fx_sub(fx_mul(a[1][1], a[2][2], stats), fx_mul(a[1][2], a[2][1], stats), stats)
    cof[0][1] = fx_sub(fx_mul(a[1][2], a[2][0], stats), fx_mul(a[1][0], a[2][2], stats), stats)
    cof[0][2] = fx_sub(fx_mul(a[1][0], a[2][1], stats), fx_mul(a[1][1], a[2][0], stats), stats)
    cof[1][0] = fx_sub(fx_mul(a[0][2], a[2][1], stats), fx_mul(a[0][1], a[2][2], stats), stats)
    cof[1][1] = fx_sub(fx_mul(a[0][0], a[2][2], stats), fx_mul(a[0][2], a[2][0], stats), stats)
    cof[1][2] = fx_sub(fx_mul(a[0][1], a[2][0], stats), fx_mul(a[0][0], a[2][1], stats), stats)
    cof[2][0] = fx_sub(fx_mul(a[0][1], a[1][2], stats), fx_mul(a[0][2], a[1][1], stats), stats)
    cof[2][1] = fx_sub(fx_mul(a[0][2], a[1][0], stats), fx_mul(a[0][0], a[1][2], stats), stats)
    cof[2][2] = fx_sub(fx_mul(a[0][0], a[1][1], stats), fx_mul(a[0][1], a[1][0], stats), stats)
    determinant = fx_mac(((a[0][j], cof[0][j]) for j in range(3)), stats)
    floored = False
    if abs(determinant) < DET_FLOOR:
        floored = True
        if stats is not None:
            stats.determinant_floor_count += 1
        determinant = DET_FLOOR if determinant >= 0 else -DET_FLOOR
    inverse = [[fx_div(cof[j][i], determinant, stats) for j in range(3)] for i in range(3)]
    return inverse, determinant, floored


def make_rsqrt_lut() -> np.ndarray:
    values = np.empty(RSQRT_DEPTH, dtype=np.int64)
    for address in range(RSQRT_DEPTH):
        # Use bin centers; nominal diagonal is >=0.106, so address zero is only a guard value.
        x_value = (address + 0.5) / 1024.0
        values[address] = quantize_scalar(1.0 / math.sqrt(x_value))
    return values


def rsqrt_lookup(diagonal: int, lut: np.ndarray, stats: ArithmeticStats | None = None) -> int:
    value = int(diagonal)
    if value < DIAG_FLOOR:
        value = DIAG_FLOOR
        if stats is not None:
            stats.diagonal_floor_count += 1
    address = value >> RSQRT_ADDR_SHIFT
    address = min(max(address, 0), RSQRT_DEPTH - 1)
    return int(lut[address])


def make_asin_lut() -> np.ndarray:
    values = np.empty(ASIN_DEPTH, dtype=np.int64)
    for address in range(ASIN_DEPTH):
        correlation = -1.0 + address / 2048.0
        values[address] = quantize_scalar((2.0 / math.pi) * math.asin(correlation))
    return values


def asin_lookup(correlation: int, lut: np.ndarray, stats: ArithmeticStats | None = None) -> int:
    value = int(correlation)
    if value > ONE:
        value = ONE
        if stats is not None:
            stats.correlation_clamp_count += 1
    elif value < -ONE:
        value = -ONE
        if stats is not None:
            stats.correlation_clamp_count += 1
    address = (value + ONE) >> ASIN_ADDR_SHIFT
    return int(lut[min(max(address, 0), ASIN_DEPTH - 1)])


def to_matrix(value: np.ndarray) -> list[list[int]]:
    array = np.asarray(value, dtype=np.int64).reshape(3, 3)
    return [[int(array[i, j]) for j in range(3)] for i in range(3)]


def to_vector(value: np.ndarray) -> list[int]:
    return [int(item) for item in np.asarray(value, dtype=np.int64).reshape(3)]


def array_from_matrix(value: list[list[int]]) -> np.ndarray:
    return np.asarray(value, dtype=np.int64)
