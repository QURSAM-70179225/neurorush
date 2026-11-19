#!/usr/bin/env python3
"""Checks docs/store/listing.md against Google Play's character limits."""
import re
import sys
from pathlib import Path

text = Path(__file__).resolve().parent.parent.joinpath("docs/store/listing.md").read_text(encoding="utf-8")
title = re.search(r"## App name.*?\n\*\*(.+?)\*\*", text, re.S).group(1)
short = re.search(r"## Short description.*?\n(.+?)\n", text, re.S).group(1)
full = text.split("## Full description (max 4000)\n", 1)[1].split("\n## Keywords", 1)[0].strip()
limits = [("App name", title, 30), ("Short description", short, 80), ("Full description", full, 4000)]
ok = True
for name, value, limit in limits:
    status = "OK" if len(value) <= limit else "TOO LONG"
    ok &= len(value) <= limit
    print(f"{name}: {len(value)}/{limit} {status}")
sys.exit(0 if ok else 1)
