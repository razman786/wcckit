#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Normalize first-round BCC ustat/ucalls/uflow text into JSONL and summary LP.

BCC language runtime tools can emit compiler warnings or probe-availability
errors before any useful rows.  Those lines are diagnostic status, not runtime
events, so this parser keeps them out of event counts.  Method/syscall names are
kept in JSONL only; Influx receives bounded summaries to avoid cardinality
explosion.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path


ERROR_PREFIXES = (
    "failed to enable usdt probe",
    "the specified pid might not contain",
    "or the runtime was not built",
    "look for a configure flag",
    "for a configure flag",
    "to check which probes",
    "wcckit uflow unavailable",
)
NOISE_PREFIXES = (
    "in file included from",
    "arch/",
    "include/",
    "<scratch space>",
    "<built-in>",
    "note:",
    "warning:",
    "tracing calls in process",
    "attached kernel tracepoints",
    "detaching kernel probes",
)
HEADER_PREFIXES = (
    "method",
    "pid ",
    "language",
)


def esc_tag(value: object) -> str:
    return str(value).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def classify_line(line: str) -> str:
    stripped = line.strip()
    if not stripped:
        return "blank"
    low = stripped.lower()
    if low.startswith(ERROR_PREFIXES):
        return "error"
    if low.startswith(NOISE_PREFIXES) or low.endswith("warnings generated."):
        return "noise"
    if re.match(r"^\d+\s*\|", stripped) or stripped.startswith("|"):
        return "noise"
    if low.startswith(HEADER_PREFIXES):
        return "header"
    if set(stripped) <= {"|", "^", "~", "-", " ", ":"}:
        return "noise"
    return "event"


def parse_ucalls_row(stripped: str) -> dict[str, object] | None:
    parts = stripped.split()
    if len(parts) < 3:
        return None
    try:
        calls = int(parts[-2])
        total_us = float(parts[-1])
    except ValueError:
        return None
    method = " ".join(parts[:-2])
    if not method:
        return None
    avg_us = total_us / calls if calls else 0.0
    return {"method": method, "calls": calls, "total_us": total_us, "avg_us": avg_us}


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

    rows_total = 0
    events_total = 0
    errors_total = 0
    max_depth = 0
    total_us = 0.0

    args.jsonl.parent.mkdir(parents=True, exist_ok=True)
    args.line_protocol.parent.mkdir(parents=True, exist_ok=True)
    with args.input.open(errors="replace") as src, args.jsonl.open("w") as jout:
        for raw in src:
            line = raw.rstrip("\n")
            stripped = line.strip()
            kind = classify_line(line)
            if kind == "error":
                errors_total += 1
                continue
            if kind != "event":
                continue

            depth = (len(line) - len(line.lstrip())) // 2
            max_depth = max(max_depth, depth)
            rec: dict[str, object] = {
                "ts_ns": time.time_ns(),
                "run_id": args.run_id,
                "pipeline": args.pipeline,
                "tool": args.tool,
                "language": args.language,
                "pid": int(args.pid),
                "depth": depth,
                "raw": stripped,
            }

            parsed = parse_ucalls_row(stripped) if args.tool == "ucalls" else None
            if parsed:
                rec.update(parsed)
                events_total += int(parsed["calls"])
                total_us += float(parsed["total_us"])
            else:
                parts = stripped.split()
                if args.tool in {"ucalls", "uflow"} and parts:
                    rec["method"] = parts[-1]
                events_total += 1

            rows_total += 1
            jout.write(json.dumps(rec, sort_keys=True) + "\n")

    measurement = {"ustat": "wcckit_app_ustat", "ucalls": "wcckit_app_ucalls", "uflow": "wcckit_app_uflow_summary"}[args.tool]
    available = "true" if events_total > 0 else "false"
    with args.line_protocol.open("w") as lp:
        lp.write(
            f"{measurement},run_id={esc_tag(args.run_id)},pipeline={esc_tag(args.pipeline)},"
            f"language={esc_tag(args.language)},pid={args.pid},tool={args.tool} "
            f"events_total={events_total}i,rows_total={rows_total}i,max_depth={max_depth}i,"
            f"errors_total={errors_total}i,total_us={total_us},available={available} {time.time_ns()}\n"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
