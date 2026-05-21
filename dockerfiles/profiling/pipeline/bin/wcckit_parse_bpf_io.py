#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Parse a conservative subset of biosnoop-style output into JSONL and Influx LP."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def esc_tag(value: object) -> str:
    return str(value).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def parse_line(line: str) -> dict[str, object] | None:
    parts = line.split()
    if not parts or parts[0].upper().startswith("TIME") or parts[0].startswith("Tracing"):
        return None
    record: dict[str, object] = {"raw": line}
    try:
        if len(parts) >= 8:
            record.update({
                "time_s": float(parts[0]),
                "comm": parts[1],
                "pid": int(parts[2]) if parts[2].isdigit() else parts[2],
                "device": parts[3],
                "operation": parts[4],
                "sector": int(parts[5]) if parts[5].isdigit() else parts[5],
                "bytes": int(parts[6]) if parts[6].isdigit() else parts[6],
                "latency_ms": float(parts[7]),
                "latency_us": float(parts[7]) * 1000.0,
            })
    except ValueError:
        return record
    return record


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--jsonl", required=True, type=Path)
    parser.add_argument("--line-protocol", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--pipeline", required=True)
    args = parser.parse_args()
    count = 0
    total_bytes = 0
    latencies: list[float] = []
    ts_ns = time.time_ns()
    args.jsonl.parent.mkdir(parents=True, exist_ok=True)
    args.line_protocol.parent.mkdir(parents=True, exist_ok=True)
    with args.input.open(errors="replace") as src, args.jsonl.open("w") as jout:
        for line in src:
            rec = parse_line(line.strip())
            if not rec:
                continue
            rec.update({"run_id": args.run_id, "pipeline": args.pipeline, "tool": "biosnoop"})
            jout.write(json.dumps(rec, sort_keys=True) + "\n")
            count += 1
            if isinstance(rec.get("bytes"), int):
                total_bytes += int(rec["bytes"])
            if isinstance(rec.get("latency_us"), float):
                latencies.append(float(rec["latency_us"]))
    avg_latency = sum(latencies) / len(latencies) if latencies else 0.0
    with args.line_protocol.open("w") as lp:
        lp.write(f"wcckit_bpf_io_summary,run_id={esc_tag(args.run_id)},pipeline={esc_tag(args.pipeline)},tool=biosnoop events_total={count}i,bytes={total_bytes}i,avg_latency_us={avg_latency} {ts_ns}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
