#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Parse conservative AMDuProfPcm CSV-like output into JSONL and Influx LP."""
from __future__ import annotations

import argparse
import csv
import json
import re
import time
from pathlib import Path
from typing import Iterable


def esc_tag(value: object) -> str:
    return str(value).replace("\\", r"\\").replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def safe_key(value: str) -> str:
    key = re.sub(r"[^A-Za-z0-9_]+", "_", value.strip().lower()).strip("_")
    if not key:
        return "value"
    if key[0].isdigit():
        key = "counter_" + key
    return key[:96]


def numeric(value: str) -> float | None:
    text = value.strip().replace(",", "")
    if not text or text.lower() in {"nan", "inf", "-inf", "n/a", "na"}:
        return None
    text = text.rstrip("%")
    try:
        return float(text)
    except ValueError:
        return None


INT_FIELDS = {
    "cycles_not_in_halt",
    "events_total",
    "locked_instructions_pti",
    "retired_instructions",
    "retired_macro_ops",
}


def elapsed_ns(value: str) -> int | None:
    """Parse AMDuProfPcm elapsed timestamps such as HH:MM:SS:mmm."""
    text = value.strip()
    match = re.match(r"^(\d+):(\d{2}):(\d{2}):(\d{1,9})$", text)
    if not match:
        return None
    hours, minutes, seconds, fraction = match.groups()
    frac_ns = int((fraction + "0" * 9)[:9])
    total_seconds = int(hours) * 3600 + int(minutes) * 60 + int(seconds)
    return total_seconds * 1_000_000_000 + frac_ns


def lp_value(field: str, value: float) -> str:
    if field in INT_FIELDS and value.is_integer():
        return f"{int(value)}i"
    if value.is_integer():
        return f"{value:.1f}"
    return repr(value)


def map_field(name: str, value: float) -> tuple[str, float]:
    low = name.lower()
    if "ipc" in low:
        return "ipc", value
    if "cpi" in low:
        return "cpi", value
    if "freq" in low or "clock" in low:
        # AMDuProfPcm versions differ between MHz and GHz labels. If the header
        # says GHz keep it as-is; otherwise convert obvious MHz values.
        if "ghz" not in low and value > 100:
            return "frequency_ghz", value / 1000.0
        return "frequency_ghz", value
    if "util" in low or "cpu" in low and "%" in low:
        return "cpu_percent", value
    if "l3" in low and "miss" in low:
        return "l3_miss_ratio", value
    if ("mem" in low or "dram" in low) and "read" in low:
        return "memory_read_gbs", value
    if ("mem" in low or "dram" in low) and "write" in low:
        return "memory_write_gbs", value
    if "package" in low and ("watt" in low or "power" in low):
        return "package_watts", value
    if "core" in low and ("watt" in low or "power" in low):
        return "core_watts", value
    if "interval" in low or "elapsed" in low or low in {"time", "duration"}:
        return "interval_s", value
    return safe_key(name), value


def likely_header(row: list[str]) -> bool:
    if len(row) < 2:
        return False
    values = [numeric(cell) for cell in row]
    return sum(v is None for v in values) >= max(1, len(row) // 2)


def rows(path: Path) -> Iterable[list[str]]:
    with path.open(newline="", errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                parsed = next(csv.reader([line]))
            except csv.Error:
                continue
            yield [cell.strip() for cell in parsed]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--jsonl", required=True, type=Path)
    parser.add_argument("--line-protocol", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--pipeline", required=True)
    parser.add_argument("--pid", required=True)
    parser.add_argument("--vendor", required=True)
    parser.add_argument("--tool", default="amd-uprof-pcm")
    parser.add_argument("--measurement", default="wcckit_amd_uprof_pcm")
    parser.add_argument("--start-timestamp-ns", type=int, default=0)
    args = parser.parse_args()

    args.jsonl.parent.mkdir(parents=True, exist_ok=True)
    args.line_protocol.parent.mkdir(parents=True, exist_ok=True)

    header: list[str] | None = None
    records = 0
    numeric_fields_total = 0
    ts_ns = time.time_ns()

    with args.jsonl.open("w") as jout, args.line_protocol.open("w") as lp:
        for row in rows(args.input):
            if likely_header(row):
                header = [safe_key(cell) or f"field_{idx}" for idx, cell in enumerate(row)]
                continue
            if header is None or len(row) < 2:
                continue
            rec_fields: dict[str, float] = {}
            raw_fields: dict[str, str] = {}
            sample_elapsed_ns: int | None = None
            for idx, cell in enumerate(row[: len(header)]):
                raw_name = header[idx]
                if raw_name == "timestamp":
                    sample_elapsed_ns = elapsed_ns(cell)
                    if cell:
                        raw_fields[raw_name] = cell
                    continue
                val = numeric(cell)
                if val is None:
                    if cell:
                        raw_fields[raw_name] = cell
                    continue
                mapped_name, mapped_value = map_field(raw_name, val)
                rec_fields[mapped_name] = mapped_value
            if not rec_fields:
                continue
            records += 1
            numeric_fields_total += len(rec_fields)
            now = (args.start_timestamp_ns + sample_elapsed_ns) if args.start_timestamp_ns and sample_elapsed_ns is not None else time.time_ns()
            record = {
                "ts_ns": now,
                "run_id": args.run_id,
                "pipeline": args.pipeline,
                "pid": int(args.pid),
                "vendor": args.vendor,
                "tool": args.tool,
                "sample_index": records,
                "fields": rec_fields,
            }
            if raw_fields:
                record["raw_labels"] = raw_fields
            jout.write(json.dumps(record, sort_keys=True) + "\n")
            fields_lp = ",".join(f"{safe_key(k)}={lp_value(safe_key(k), v)}" for k, v in sorted(rec_fields.items()))
            lp.write(
                f"{args.measurement},run_id={esc_tag(args.run_id)},pipeline={esc_tag(args.pipeline)},"
                f"pid={args.pid},tool={esc_tag(args.tool)},vendor={esc_tag(args.vendor)} {fields_lp} {now}\n"
            )
        lp.write(
            f"wcckit_amd_uprof_status,run_id={esc_tag(args.run_id)},pipeline={esc_tag(args.pipeline)},"
            f"pid={args.pid},tool={esc_tag(args.tool)},vendor={esc_tag(args.vendor)} "
            f"available=true,events_total={records}i,numeric_fields_total={numeric_fields_total}i {ts_ns}\n"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
