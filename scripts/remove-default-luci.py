#!/usr/bin/env python3
"""Exclude the LuCI collection metapackage from qualcommax defaults.

The 'luci' collection depends on luci-app-package-manager. This firmware
selects its required LuCI components explicitly in configs/core.config.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def remove_default_luci(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    in_defaults = False
    seen_defaults = False
    changed = False

    for index, line in enumerate(lines):
        if not in_defaults and re.match(r"^\s*DEFAULT_PACKAGES\s*\+=", line):
            in_defaults = True
            seen_defaults = True

        if in_defaults:
            # Standalone word only; preserve luci-base / luci-app-* packages.
            modified = re.sub(r"(?<!\S)luci(?=\s|$)", "", line)
            if modified != line:
                lines[index] = modified
                changed = True
            if not line.rstrip().endswith("\\"):
                in_defaults = False

    if not seen_defaults:
        raise ValueError("No DEFAULT_PACKAGES assignment found in target Makefile")
    if any(
        re.search(r"(?<!\S)luci(?=\s|$)", line)
        for line in lines
        if not line.lstrip().startswith("#") and "DEFAULT_PACKAGES" in line
    ):
        raise ValueError("luci metapackage remains in target defaults")
    return "".join(lines), changed


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: remove-default-luci.py <qualcommax/Makefile>", file=sys.stderr)
        return 64
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"ERROR: target Makefile not found: {path}", file=sys.stderr)
        return 1

    try:
        patched, changed = remove_default_luci(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if changed:
        path.write_text(patched, encoding="utf-8")
        print("Removed LuCI collection metapackage from qualcommax defaults")
    else:
        print("LuCI collection metapackage already absent from target defaults")
    return 0


if __name__ == "__main__":
    sys.exit(main())
