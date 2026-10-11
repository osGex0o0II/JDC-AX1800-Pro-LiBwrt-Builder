#!/usr/bin/env python3
"""Remove the LuCI collection without removing the LuCI admin applications.

LiBwrt includes 'luci' from qualcommax DEFAULT_PACKAGES *and*
include/target.mk DEFAULT_PACKAGES.tweak. The 'luci' collection depends on
luci-app-package-manager; core.config selects the needed admin UI explicitly.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DEFAULTS = re.compile(r"^\s*DEFAULT_PACKAGES(?:\.tweak)?\s*(?:\+=|:=|=)")
LUCI_TOKEN = re.compile(r"(?<!\S)luci(?=\s|$)")


def remove_default_luci(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    in_defaults = False
    seen_defaults = False
    changed = False

    for index, line in enumerate(lines):
        if not in_defaults and DEFAULTS.match(line):
            in_defaults = True
            seen_defaults = True

        if in_defaults:
            modified = LUCI_TOKEN.sub("", line)
            if modified != line:
                lines[index] = modified
                changed = True
            if not line.rstrip().endswith("\\"):
                in_defaults = False

    if not seen_defaults:
        raise ValueError("No DEFAULT_PACKAGES or DEFAULT_PACKAGES.tweak assignment found")
    return "".join(lines), changed


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: remove-default-luci.py <target Makefile> [<include/target.mk> ...]", file=sys.stderr)
        return 64

    for name in sys.argv[1:]:
        path = Path(name)
        if not path.is_file():
            print(f"ERROR: target defaults file not found: {path}", file=sys.stderr)
            return 1
        try:
            patched, changed = remove_default_luci(path.read_text(encoding="utf-8"))
        except ValueError as exc:
            print(f"ERROR: {path}: {exc}", file=sys.stderr)
            return 1
        if changed:
            path.write_text(patched, encoding="utf-8")
            print(f"Removed LuCI collection metapackage from {path}")
        else:
            print(f"LuCI collection metapackage already absent from {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
