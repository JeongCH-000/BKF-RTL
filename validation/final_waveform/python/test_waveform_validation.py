#!/usr/bin/env python3
"""Mutation checks for the archived cycle and VCD timing validators."""
from __future__ import annotations

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run_waveform_validation as validator


class WaveformValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        validator.recheck_fixed_model('ekf_l1')

    def test_original_evidence_passes(self):
        validator.verify_evidence('ekf_l1')

    def check_cycle_mutation(self, field, value, expected_error):
        original_read_csv = validator.read_csv

        def mutated_read_csv(path):
            rows = original_read_csv(path)
            if path.name == 'cycle_counts_ekf.csv':
                rows[1][field] = value
            return rows

        with patch.object(validator, 'read_csv', side_effect=mutated_read_csv):
            with self.assertRaisesRegex(RuntimeError, expected_error):
                validator.verify_evidence('ekf_l1')

    def test_duplicate_cycle_step_is_rejected(self):
        self.check_cycle_mutation('step', '0', 'ordered archived cycle rows')

    def test_inconsistent_result_cycle_is_rejected(self):
        self.check_cycle_mutation('result_cycle', '9999999', 'result/start cycle mismatch')

    def check_vcd_header(self, header, expected_error):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.vcd'
            path.write_text(header + '$enddefinitions $end\n')
            # The parser can reject timing metadata before reading signal data.
            # Use tracked vectors so this test also runs on a clean checkout.
            with patch.object(validator, 'ROOT', validator.SOURCE):
                with patch.object(validator, 'wave_path', return_value=path):
                    with self.assertRaisesRegex(RuntimeError, expected_error):
                        validator.inspect_vcd('ekf_l1', 'full', 10)

    def test_changed_vcd_timescale_is_rejected(self):
        original = '$timescale\n\t1ps\n$end\n'
        self.check_vcd_header(original.replace('1ps', '1ns'), 'expected VCD timescale 1ps')

    def test_missing_vcd_timescale_is_rejected(self):
        self.check_vcd_header('', 'missing VCD timescale 1ps')

    def test_duplicate_vcd_timescale_is_rejected(self):
        self.check_vcd_header('$timescale 1 ps $end\n' * 2, 'duplicate VCD timescale')

    def test_unterminated_vcd_timescale_is_rejected(self):
        # No $end anywhere: keep the fixture separate from check_vcd_header.
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.vcd'
            path.write_text('$timescale\n1ps\n')
            with patch.object(validator, 'ROOT', validator.SOURCE):
                with patch.object(validator, 'wave_path', return_value=path):
                    with self.assertRaisesRegex(RuntimeError, 'unterminated VCD timescale'):
                        validator.inspect_vcd('ekf_l1', 'full', 10)


if __name__ == '__main__':
    unittest.main()
