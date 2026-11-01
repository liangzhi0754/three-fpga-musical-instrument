import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PinManifestTests(unittest.TestCase):
    def test_manifest_matches_all_constraints(self):
        manifest = json.loads((ROOT / "pin_confirmation.json").read_text(encoding="utf-8"))
        for board in "ABC":
            constraints = (ROOT / "projects" / board / "pins.cst").read_text(encoding="utf-8")
            actual = {name: int(pin) for name, pin in
                      re.findall(r'IO_LOC\s+"([^"]+)"\s+(\d+)\s*;', constraints)}
            self.assertEqual(actual, manifest["boards"][board], board)
            self.assertEqual(len(actual), len(set(actual.values())), board)

    def test_release_does_not_claim_physical_validation(self):
        manifest = json.loads((ROOT / "pin_confirmation.json").read_text(encoding="utf-8"))
        self.assertFalse(manifest["hardware_ready"])
        self.assertFalse(manifest["physical_three_board_test_passed"])


if __name__ == "__main__":
    unittest.main()
