"""Load nominal.yaml and verify that it matches the fixed RTL interface."""

from __future__ import annotations

import ast
import hashlib
import math
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "nominal.yaml"


class NominalConfigError(RuntimeError):
    """Raised when the nominal configuration is malformed or RTL-incompatible."""


_SCHEMA = {
    "system": {
        "state_dimension", "feature_dimension", "sigma", "rho", "beta",
        "sampling_interval", "taylor_order",
    },
    "experiment": {
        "seed", "steps", "rbkf_branches", "initial_state",
        "initial_covariance_diagonal",
    },
    "noise": {
        "process_covariance_diagonal", "measurement_covariance_diagonal",
    },
    "fixed_point": {
        "signed_width", "fractional_bits", "rounding", "saturation",
    },
}


def _decode_scalar(text: str, line_number: int) -> Any:
    try:
        return ast.literal_eval(text)
    except (SyntaxError, ValueError):
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", text):
            return text
        raise NominalConfigError(
            f"{CONFIG_PATH}:{line_number}: unsupported YAML scalar {text!r}"
        ) from None


def load_nominal_config(path: Path = CONFIG_PATH) -> dict[str, dict[str, Any]]:
    """Parse the project's deliberately small two-level YAML schema."""
    sections: dict[str, dict[str, Any]] = {}
    current_section: str | None = None
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise NominalConfigError(f"Cannot read nominal configuration {path}: {error}") from error

    for line_number, raw_line in enumerate(lines, 1):
        if "\t" in raw_line:
            raise NominalConfigError(f"{path}:{line_number}: tabs are not allowed")
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indentation = len(line) - len(line.lstrip(" "))
        content = line.lstrip(" ")
        if indentation == 0:
            if not content.endswith(":") or content.count(":") != 1:
                raise NominalConfigError(
                    f"{path}:{line_number}: expected a top-level 'section:'"
                )
            current_section = content[:-1].strip()
            if current_section in sections:
                raise NominalConfigError(
                    f"{path}:{line_number}: duplicate section {current_section!r}"
                )
            sections[current_section] = {}
            continue
        if indentation != 2 or current_section is None:
            raise NominalConfigError(
                f"{path}:{line_number}: expected a two-space-indented 'key: value'"
            )
        key, separator, value_text = content.partition(":")
        key = key.strip()
        value_text = value_text.strip()
        if not separator or not key or not value_text:
            raise NominalConfigError(f"{path}:{line_number}: expected 'key: value'")
        if key in sections[current_section]:
            raise NominalConfigError(f"{path}:{line_number}: duplicate key {key!r}")
        sections[current_section][key] = _decode_scalar(value_text, line_number)

    unknown_sections = set(sections) - set(_SCHEMA)
    missing_sections = set(_SCHEMA) - set(sections)
    schema_errors: list[str] = []
    if unknown_sections:
        schema_errors.append(f"unknown sections: {sorted(unknown_sections)}")
    if missing_sections:
        schema_errors.append(f"missing sections: {sorted(missing_sections)}")
    for section in set(sections) & set(_SCHEMA):
        unknown_keys = set(sections[section]) - _SCHEMA[section]
        missing_keys = _SCHEMA[section] - set(sections[section])
        if unknown_keys:
            schema_errors.append(f"{section}: unknown keys {sorted(unknown_keys)}")
        if missing_keys:
            schema_errors.append(f"{section}: missing keys {sorted(missing_keys)}")
    if schema_errors:
        raise NominalConfigError(
            f"{path}: invalid nominal configuration schema:\n  - "
            + "\n  - ".join(schema_errors)
        )
    return sections


def _integer(section: str, key: str) -> int:
    value = CONFIG[section][key]
    if isinstance(value, bool) or not isinstance(value, int):
        raise NominalConfigError(f"{CONFIG_PATH}: {section}.{key} must be an integer")
    return value


def _number(section: str, key: str) -> float:
    value = CONFIG[section][key]
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise NominalConfigError(f"{CONFIG_PATH}: {section}.{key} must be a finite number")
    return float(value)


def _string(section: str, key: str) -> str:
    value = CONFIG[section][key]
    if not isinstance(value, str):
        raise NominalConfigError(f"{CONFIG_PATH}: {section}.{key} must be a string")
    return value


CONFIG = load_nominal_config()
CONFIG_SHA256 = hashlib.sha256(CONFIG_PATH.read_bytes()).hexdigest()

STATE_DIMENSION = _integer("system", "state_dimension")
FEATURE_DIMENSION = _integer("system", "feature_dimension")
SIGMA = _number("system", "sigma")
RHO = _number("system", "rho")
BETA = _number("system", "beta")
SAMPLING_INTERVAL = _number("system", "sampling_interval")
TAYLOR_ORDER = _integer("system", "taylor_order")

SEED = _integer("experiment", "seed")
STEPS = _integer("experiment", "steps")
RBKF_BRANCHES = _integer("experiment", "rbkf_branches")
_initial_state = CONFIG["experiment"]["initial_state"]
if not isinstance(_initial_state, (list, tuple)):
    raise NominalConfigError(f"{CONFIG_PATH}: experiment.initial_state must be a number list")
if any(
    isinstance(item, bool)
    or not isinstance(item, (int, float))
    or not math.isfinite(item)
    for item in _initial_state
):
    raise NominalConfigError(f"{CONFIG_PATH}: experiment.initial_state must contain only numbers")
INITIAL_STATE = tuple(float(item) for item in _initial_state)
INITIAL_COVARIANCE_DIAGONAL = _number("experiment", "initial_covariance_diagonal")

PROCESS_COVARIANCE_DIAGONAL = _number("noise", "process_covariance_diagonal")
MEASUREMENT_COVARIANCE_DIAGONAL = _number("noise", "measurement_covariance_diagonal")

SIGNED_WIDTH = _integer("fixed_point", "signed_width")
FRACTIONAL_BITS = _integer("fixed_point", "fractional_bits")
ROUNDING = _string("fixed_point", "rounding")
SATURATION = _string("fixed_point", "saturation")


def quantize_config_value(value: float) -> int:
    """Quantize a scalar using nominal.yaml's fixed-point contract."""
    scale = 1 << FRACTIONAL_BITS
    magnitude = int(math.floor(abs(float(value)) * scale + 0.5))
    quantized = -magnitude if value < 0 else magnitude
    minimum = -(1 << (SIGNED_WIDTH - 1))
    maximum = (1 << (SIGNED_WIDTH - 1)) - 1
    return min(max(quantized, minimum), maximum)


def _parse_verilog_integer(token: str, location: str) -> int:
    token = token.strip().replace("_", "")
    match = re.fullmatch(
        r"(?P<sign>[+-]?)(?:(?P<width>\d+)'(?P<signed>[sS]?)(?P<base>[dDhHbB])"
        r"(?P<digits>[0-9a-fA-F]+)|(?P<plain>\d+))",
        token,
    )
    if match is None:
        raise NominalConfigError(f"Cannot parse RTL integer {token!r} at {location}")
    if match.group("plain") is not None:
        value = int(match.group("plain"), 10)
    else:
        base = {"d": 10, "h": 16, "b": 2}[match.group("base").lower()]
        value = int(match.group("digits"), base)
    return -value if match.group("sign") == "-" else value


def _macro_value(source: str, name: str, path: Path) -> int:
    match = re.search(rf"^\s*`define\s+{re.escape(name)}\s+(\S+)", source, re.MULTILINE)
    if match is None:
        raise NominalConfigError(f"Missing `{name} in {path}")
    return _parse_verilog_integer(match.group(1), f"{path}: `{name}")


def _localparam_value(source: str, name: str, path: Path) -> int:
    match = re.search(
        rf"\blocalparam\b[^;\n]*\b{re.escape(name)}\s*=\s*([^;\s]+)\s*;",
        source,
    )
    if match is None:
        raise NominalConfigError(f"Missing localparam {name} in {path}")
    return _parse_verilog_integer(match.group(1), f"{path}: {name}")


def validate_rtl_compatibility() -> None:
    """Fail before vector generation if YAML cannot describe this fixed RTL."""
    errors: list[str] = []
    if STATE_DIMENSION != 3:
        errors.append(f"system.state_dimension={STATE_DIMENSION}; RTL supports exactly 3")
    if FEATURE_DIMENSION != 3:
        errors.append(f"system.feature_dimension={FEATURE_DIMENSION}; RTL supports exactly 3")
    if len(INITIAL_STATE) != STATE_DIMENSION:
        errors.append(
            f"experiment.initial_state has {len(INITIAL_STATE)} entries; expected {STATE_DIMENSION}"
        )
    if RBKF_BRANCHES != 8:
        errors.append(f"experiment.rbkf_branches={RBKF_BRANCHES}; nominal RTL supports L=8")
    if STEPS != 500:
        errors.append(
            f"experiment.steps={STEPS}; the RTL regression contract requires exactly 500"
        )
    if SEED < 0:
        errors.append(f"experiment.seed={SEED}; expected a non-negative integer")
    if SAMPLING_INTERVAL <= 0.0:
        errors.append("system.sampling_interval must be positive")
    if TAYLOR_ORDER < 1:
        errors.append("system.taylor_order must be positive")
    if INITIAL_COVARIANCE_DIAGONAL < 0.0:
        errors.append("experiment.initial_covariance_diagonal must be non-negative")
    if PROCESS_COVARIANCE_DIAGONAL < 0.0:
        errors.append("noise.process_covariance_diagonal must be non-negative")
    if MEASUREMENT_COVARIANCE_DIAGONAL <= 0.0:
        errors.append("noise.measurement_covariance_diagonal must be positive")
    fixed_dimensions_valid = (
        SIGNED_WIDTH >= 2 and 0 < FRACTIONAL_BITS < SIGNED_WIDTH
    )
    if not fixed_dimensions_valid:
        errors.append(
            f"invalid fixed-point dimensions width={SIGNED_WIDTH}, fractional_bits={FRACTIONAL_BITS}"
        )
    if ROUNDING != "nearest_ties_away_from_zero":
        errors.append(
            f"fixed_point.rounding={ROUNDING!r}; RTL uses 'nearest_ties_away_from_zero'"
        )
    expected_saturation = f"signed_{SIGNED_WIDTH}_bit"
    if SATURATION != expected_saturation:
        errors.append(
            f"fixed_point.saturation={SATURATION!r}; expected {expected_saturation!r}"
        )

    definitions_path = ROOT / "rtl" / "common" / "fx_q8_16_defs.vh"
    core_path = ROOT / "rtl" / "bkf" / "bkf_core.v"
    try:
        definitions = definitions_path.read_text(encoding="utf-8")
        core = core_path.read_text(encoding="utf-8")
        expected_constants = {
            "WIDTH": SIGNED_WIDTH,
            "FRAC": FRACTIONAL_BITS,
        }
        if fixed_dimensions_valid:
            expected_constants.update({
                "ONE": 1 << FRACTIONAL_BITS,
                "Q_DIAG": quantize_config_value(PROCESS_COVARIANCE_DIAGONAL),
                "R_DIAG": quantize_config_value(MEASUREMENT_COVARIANCE_DIAGONAL),
                "ALPHA": quantize_config_value(math.sqrt(2.0 / math.pi)),
            })
        macro_names = {
            "WIDTH": "FX_Q8_16_WIDTH", "FRAC": "FX_Q8_16_FRAC",
            "ONE": "FX_Q8_16_ONE", "Q_DIAG": "FX_Q8_16_Q_DIAG",
            "R_DIAG": "FX_Q8_16_R_DIAG", "ALPHA": "FX_Q8_16_ALPHA",
        }
        for label, expected in expected_constants.items():
            actual = _macro_value(definitions, macro_names[label], definitions_path)
            if actual != expected:
                errors.append(
                    f"{macro_names[label]}={actual} in RTL, but nominal.yaml requires {expected}"
                )
        for label in ("ONE", "Q_DIAG", "R_DIAG", "ALPHA"):
            if label not in expected_constants:
                continue
            core_name = "FX_ONE" if label == "ONE" else label
            actual = _localparam_value(core, core_name, core_path)
            expected = expected_constants[label]
            if actual != expected:
                errors.append(
                    f"{core_name}={actual} in bkf_core.v, but nominal.yaml requires {expected}"
                )
        if not re.search(r"NUM_BRANCHES\s*==\s*8", core):
            errors.append("bkf_core.v no longer contains the required NUM_BRANCHES==8 datapath")
    except (OSError, NominalConfigError) as error:
        errors.append(str(error))

    if errors:
        raise NominalConfigError(
            f"{CONFIG_PATH}: nominal configuration is incompatible with the fixed RTL:\n  - "
            + "\n  - ".join(errors)
        )


validate_rtl_compatibility()
