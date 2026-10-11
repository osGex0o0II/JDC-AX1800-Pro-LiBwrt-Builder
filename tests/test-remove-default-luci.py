#!/usr/bin/env python3
"""Regression tests for excluding only the default LuCI collection."""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "remove-default-luci.py"
SPEC = importlib.util.spec_from_file_location("remove_default_luci", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DefaultLuciTests(unittest.TestCase):
    def test_removes_only_standalone_metapackage(self) -> None:
        original = (
            "include $(TOPDIR)/rules.mk\n"
            "DEFAULT_PACKAGES += \\\n"
            "\tautocore automount luci-app-cpufreq losetup luci uboot-envtools \\\n"
            "\tluci-base luci-theme-aurora kmod-qca-nss-drv\n"
            "\n$(eval $(call BuildTarget))\n"
        )
        updated, changed = module.remove_default_luci(original)
        self.assertTrue(changed)
        self.assertNotIn(" losetup luci uboot-envtools", updated)
        self.assertIn("luci-app-cpufreq", updated)
        self.assertIn("luci-base", updated)
        self.assertIn("luci-theme-aurora", updated)
        self.assertIn("kmod-qca-nss-drv", updated)
        self.assertEqual(module.remove_default_luci(updated), (updated, False))

    def test_leaves_unrelated_makefile_lines_untouched(self) -> None:
        original = (
            "MY_PACKAGE := luci\n"
            "DEFAULT_PACKAGES += luci luci-base\n"
            "OTHER_PACKAGE := luci\n"
        )
        patched, changed = module.remove_default_luci(original)
        self.assertTrue(changed)
        self.assertIn("MY_PACKAGE := luci", patched)
        self.assertIn("OTHER_PACKAGE := luci", patched)
        self.assertNotIn("DEFAULT_PACKAGES += luci ", patched)

    def test_rejects_missing_default_packages_section(self) -> None:
        with self.assertRaisesRegex(ValueError, "No DEFAULT_PACKAGES"):
            module.remove_default_luci("OTHER_PACKAGES += luci\n")

    def test_cli_patches_file(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            target = Path(d) / "Makefile"
            target.write_text("DEFAULT_PACKAGES += luci uhttpd luci-base\n")
            subprocess.run([sys.executable, str(SCRIPT), str(target)], check=True)
            self.assertEqual(target.read_text(), "DEFAULT_PACKAGES +=  uhttpd luci-base\n")


if __name__ == "__main__":
    unittest.main()
