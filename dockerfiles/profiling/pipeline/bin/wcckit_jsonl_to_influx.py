#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Tiny JSONL to Influx line protocol helper for bounded numeric summaries."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def esc_tag(value: object) -> str:
    return str(value).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def esc_field_string(value: str) -> str:
    return '"' + value.replace('"', r'\"') + '"'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--measurement", required=True)
    parser.add_argument("--tag", action="append", default=[])
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.input.open(errors="replace") as src, args.output.open("w") as out:
        for line in src:
            if not line.strip():
                continue
            rec = json.loads(line)
            tags = []
            fields = []
            for key in args.tag:
                if key in rec:
                    tags.append(f"{esc_tag(key)}={esc_tag(rec[key])}")
            for key, value in rec.items():
                if key in args.tag or key == "ts_ns":
                    continue
                if isinstance(value, bool):
                    fields.append(f"{key}={str(value).lower()}")
                elif isinstance(value, int):
                    fields.append(f"{key}={value}i")
                elif isinstance(value, float):
                    fields.append(f"{key}={value}")
                elif isinstance(value, str) and len(value) < 512:
                    fields.append(f"{key}={esc_field_string(value)}")
            if fields:
                tag_text = "," + ",".join(tags) if tags else ""
                out.write(f"{args.measurement}{tag_text} {','.join(fields)} {rec.get('ts_ns', time.time_ns())}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
