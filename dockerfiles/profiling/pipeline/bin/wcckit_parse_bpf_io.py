#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Parse BCC block-I/O output into JSONL and bounded Influx line protocol.

The first-round collector uses ``biolatency-bpfcc -j`` because it is reliable
across the current Ubuntu 24.04/BCC/kernel combination and gives low-cardinality
summary telemetry. The parser still understands biosnoop-style rows when they
are present, but deliberately ignores BPF compiler warnings and other startup
noise so failed/empty traces are not counted as I/O events.
"""
from __future__ import annotations

import argparse
import ast
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Any


def esc_tag(value: object) -> str:
    return str(value).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def parse_biosnoop_line(line: str) -> dict[str, object] | None:
    parts = line.split()
    if len(parts) < 8:
        return None
    if parts[0].upper().startswith("TIME") or parts[0].startswith("Tracing"):
        return None
    try:
        time_s = float(parts[0])
        latency_ms = float(parts[7])
    except ValueError:
        return None
    return {
        "source": "biosnoop",
        "time_s": time_s,
        "comm": parts[1],
        "pid": int(parts[2]) if parts[2].isdigit() else parts[2],
        "device": parts[3],
        "operation": parts[4],
        "sector": int(parts[5]) if parts[5].isdigit() else parts[5],
        "bytes": int(parts[6]) if parts[6].isdigit() else parts[6],
        "latency_ms": latency_ms,
        "latency_us": latency_ms * 1000.0,
    }


def parse_biolatency_line(line: str) -> dict[str, object] | None:
    stripped = line.strip()
    if not stripped.startswith("{") or "interval-start" not in stripped:
        return None
    try:
        data = ast.literal_eval(stripped)
    except (SyntaxError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    buckets = data.get("data")
    if not isinstance(buckets, list):
        return None

    events_total = 0
    weighted_latency = 0.0
    parsed_buckets: list[dict[str, int]] = []
    for bucket in buckets:
        if not isinstance(bucket, dict):
            continue
        try:
            start = int(bucket.get("interval-start", 0))
            end = int(bucket.get("interval-end", 0))
            count = int(bucket.get("count", 0))
        except (TypeError, ValueError):
            continue
        parsed_buckets.append({"interval_start_us": start, "interval_end_us": end, "count": count})
        events_total += count
        if count > 0:
            weighted_latency += ((start + end) / 2.0) * count

    avg_latency_us = weighted_latency / events_total if events_total else 0.0
    return {
        "source": "biolatency",
        "timestamp": data.get("ts"),
        "value_type": data.get("val_type", "usecs"),
        "events_total": events_total,
        "avg_latency_us": avg_latency_us,
        "buckets": parsed_buckets,
    }


def timestamp_ns(record: dict[str, Any], fallback: int) -> int:
    value = record.get("timestamp")
    if isinstance(value, str):
        try:
            return int(datetime.strptime(value, "%Y-%m-%d %H:%M:%S").timestamp() * 1_000_000_000)
        except ValueError:
            return fallback
    return fallback


def lp_summary(run_id: str, pipeline: str, tool: str, events_total: int, total_bytes: int, avg_latency_us: float, ts_ns: int) -> str:
    return (
        f"wcckit_bpf_io_summary,run_id={esc_tag(run_id)},pipeline={esc_tag(pipeline)},tool={esc_tag(tool)} "
        f"events_total={events_total}i,bytes={total_bytes}i,avg_latency_us={avg_latency_us} {ts_ns}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--jsonl", required=True, type=Path)
    parser.add_argument("--line-protocol", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--pipeline", required=True)
    args = parser.parse_args()

    records: list[dict[str, object]] = []
    biosnoop_count = 0
    biosnoop_bytes = 0
    biosnoop_latencies: list[float] = []
    fallback_ts = time.time_ns()

    args.jsonl.parent.mkdir(parents=True, exist_ok=True)
    args.line_protocol.parent.mkdir(parents=True, exist_ok=True)

    with args.input.open(errors="replace") as src, args.jsonl.open("w") as jout:
        for raw_line in src:
            line = raw_line.strip()
            if not line:
                continue
            rec = parse_biolatency_line(line) or parse_biosnoop_line(line)
            if rec is None:
                continue
            rec.update({"run_id": args.run_id, "pipeline": args.pipeline, "tool": rec.get("source", "bpf-io")})
            jout.write(json.dumps(rec, sort_keys=True) + "\n")
            records.append(rec)
            if rec.get("source") == "biosnoop":
                biosnoop_count += 1
                if isinstance(rec.get("bytes"), int):
                    biosnoop_bytes += int(rec["bytes"])
                if isinstance(rec.get("latency_us"), float):
                    biosnoop_latencies.append(float(rec["latency_us"]))

    with args.line_protocol.open("w") as lp:
        if records:
            for rec in records:
                if rec.get("source") != "biolatency":
                    continue
                ts_ns = timestamp_ns(rec, fallback_ts)
                lp.write(lp_summary(
                    args.run_id,
                    args.pipeline,
                    "biolatency",
                    int(rec.get("events_total", 0)),
                    0,
                    float(rec.get("avg_latency_us", 0.0)),
                    ts_ns,
                ) + "\n")
            if biosnoop_count:
                avg_latency = sum(biosnoop_latencies) / len(biosnoop_latencies) if biosnoop_latencies else 0.0
                lp.write(lp_summary(args.run_id, args.pipeline, "biosnoop", biosnoop_count, biosnoop_bytes, avg_latency, fallback_ts) + "\n")
        else:
            lp.write(lp_summary(args.run_id, args.pipeline, "bpf-io", 0, 0, 0.0, fallback_ts) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
