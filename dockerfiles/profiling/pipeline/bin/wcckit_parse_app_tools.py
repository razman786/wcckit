#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Normalize first-round BCC ustat/ucalls/uflow text into JSONL and summary LP."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def esc_tag(value: object) -> str:
    return str(value).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def keep(line: str) -> bool:
    if not line.strip():
        return False
    low = line.lower()
    return not (low.startswith("tracing") or low.startswith("warning"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tool", required=True, choices=["ustat", "ucalls", "uflow"])
    parser.add_argument("--language", required=True)
    parser.add_argument("--pid", required=True)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--jsonl", required=True, type=Path)
    parser.add_argument("--line-protocol", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--pipeline", required=True)
    args = parser.parse_args()
    count = 0
    max_depth = 0
    args.jsonl.parent.mkdir(parents=True, exist_ok=True)
    args.line_protocol.parent.mkdir(parents=True, exist_ok=True)
    with args.input.open(errors="replace") as src, args.jsonl.open("w") as jout:
        for raw in src:
            line = raw.rstrip("\n")
            if not keep(line):
                continue
            stripped = line.strip()
            depth = (len(line) - len(line.lstrip())) // 2
            max_depth = max(max_depth, depth)
            rec = {"ts_ns": time.time_ns(), "run_id": args.run_id, "pipeline": args.pipeline, "tool": args.tool, "language": args.language, "pid": int(args.pid), "depth": depth, "raw": stripped}
            parts = stripped.split()
            if args.tool in {"ucalls", "uflow"} and parts:
                rec["method"] = parts[-1]
            jout.write(json.dumps(rec, sort_keys=True) + "\n")
            count += 1
    measurement = {"ustat": "wcckit_app_ustat", "ucalls": "wcckit_app_ucalls", "uflow": "wcckit_app_uflow_summary"}[args.tool]
    with args.line_protocol.open("w") as lp:
        lp.write(f"{measurement},run_id={esc_tag(args.run_id)},pipeline={esc_tag(args.pipeline)},language={esc_tag(args.language)},pid={args.pid},tool={args.tool} events_total={count}i,max_depth={max_depth}i {time.time_ns()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
