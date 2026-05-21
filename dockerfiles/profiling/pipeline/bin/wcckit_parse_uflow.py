#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Parse BCC uflow output without dropping emitted lines.

BCC uflow output is a chronological method-flow stream, not a sampled CPU
profile.  This parser keeps every non-empty input line in JSONL.  Recognised
entry rows are also converted into folded-stack counts for interactive call-tree
views.  Return rows update the reconstructed stack but are not counted as flame
graph samples, because they are close events rather than additional work.
Unrecognised lines are preserved as raw_unparsed records so the raw archive can
be audited and the parser can be improved later.
"""
from __future__ import annotations

import argparse
import json
import re
import socket
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

EVENT_RE = re.compile(r"^\s*(?P<cpu>\d+)\s+(?P<pid>\d+)\s+(?P<tid>\d+)\s+(?P<time_us>\d+(?:\.\d+)?)(?P<rest>.*)$")
ARROW_RE = re.compile(r"(?P<indent>\s*)(?P<direction><-|->)\s+(?P<method>.+?)\s*$")


def esc_tag(value: object) -> str:
    return str(value).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def clean_symbol(value: str) -> str:
    value = value.strip() or "unknown"
    return value.replace(";", ",").replace("\n", " ")


def split_class_method(method: str) -> tuple[str, str]:
    if "." not in method:
        return "", method
    clazz, name = method.rsplit(".", 1)
    return clazz, name


def parse_event_line(line: str, method_col: int | None) -> dict[str, Any] | None:
    match = EVENT_RE.match(line)
    if not match:
        return None
    method_field = line[method_col:] if method_col is not None and len(line) >= method_col else match.group("rest")
    arrow = ARROW_RE.search(method_field)
    if not arrow:
        return None
    method = arrow.group("method").strip()
    clazz, method_name = split_class_method(method)
    depth = max(1, (len(arrow.group("indent")) // 2) + 1)
    return {
        "type": "event",
        "cpu": int(match.group("cpu")),
        "pid": int(match.group("pid")),
        "tid": int(match.group("tid")),
        "time_us": float(match.group("time_us")),
        "direction": "return" if arrow.group("direction") == "<-" else "entry",
        "depth": depth,
        "class": clazz,
        "method": method_name,
        "symbol": method,
    }


def update_folded(stacks: dict[tuple[int, int], list[str]], folded: Counter[str], event: dict[str, Any]) -> None:
    key = (int(event["pid"]), int(event["tid"]))
    symbol = clean_symbol(str(event["symbol"]))
    depth = max(1, int(event.get("depth", 1)))
    stack = stacks[key]

    if event.get("direction") == "entry":
        if len(stack) >= depth:
            stack[:] = stack[: depth - 1]
        while len(stack) < depth - 1:
            stack.append("unknown")
        stack.append(symbol)
        folded[";".join(stack)] += 1
        return

    if symbol in stack:
        idx = len(stack) - 1 - stack[::-1].index(symbol)
        stack[:] = stack[:idx]
        return

    if len(stack) >= depth:
        stack[:] = stack[: depth - 1]


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse BCC uflow output into JSONL, folded stacks, and summary LP")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--jsonl", required=True, type=Path)
    parser.add_argument("--folded", required=True, type=Path)
    parser.add_argument("--line-protocol", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--pipeline", required=True)
    parser.add_argument("--pid", required=True)
    parser.add_argument("--language", required=True, choices=["python", "java", "perl", "php", "ruby", "tcl"])
    args = parser.parse_args()

    lines = args.input.read_text(errors="replace").splitlines()
    method_col = None
    for line in lines:
        if "METHOD" in line and "TIME" in line and "PID" in line:
            method_col = line.index("METHOD")
            break

    args.jsonl.parent.mkdir(parents=True, exist_ok=True)
    args.folded.parent.mkdir(parents=True, exist_ok=True)
    args.line_protocol.parent.mkdir(parents=True, exist_ok=True)

    folded: Counter[str] = Counter()
    stacks: dict[tuple[int, int], list[str]] = defaultdict(list)
    events_total = 0
    parsed_events_total = 0
    unparsed_events_total = 0
    entry_events_total = 0
    return_events_total = 0
    max_depth = 0
    first_ts_ns = time.time_ns()

    with args.jsonl.open("w") as jout:
        for line_no, raw in enumerate(lines, start=1):
            ts_ns = time.time_ns()
            if not raw.strip():
                continue
            events_total += 1
            event = parse_event_line(raw, method_col)
            if event is None:
                unparsed_events_total += 1
                jout.write(json.dumps({
                    "type": "raw_unparsed",
                    "ts_ns": ts_ns,
                    "line_no": line_no,
                    "run_id": args.run_id,
                    "pipeline": args.pipeline,
                    "tool": "uflow",
                    "language": args.language,
                    "pid": int(args.pid),
                    "raw": raw,
                    "error": "line did not match BCC uflow event format",
                }, sort_keys=True) + "\n")
                continue

            parsed_events_total += 1
            if event["direction"] == "entry":
                entry_events_total += 1
            else:
                return_events_total += 1
            max_depth = max(max_depth, int(event["depth"]))
            event.update({
                "ts_ns": ts_ns,
                "line_no": line_no,
                "run_id": args.run_id,
                "pipeline": args.pipeline,
                "tool": "uflow",
                "language": args.language,
                "raw": raw,
            })
            update_folded(stacks, folded, event)
            jout.write(json.dumps(event, sort_keys=True) + "\n")

    with args.folded.open("w") as fout:
        for stack, count in sorted(folded.items()):
            if stack:
                fout.write(f"{stack} {count}\n")

    ts = time.time_ns()
    available = "true" if parsed_events_total > 0 else "false"
    with args.line_protocol.open("w") as lp:
        lp.write(
            f"wcckit_app_uflow_summary,run_id={esc_tag(args.run_id)},host={esc_tag(socket.gethostname())},"
            f"pipeline={esc_tag(args.pipeline)},pid={args.pid},language={esc_tag(args.language)},tool=uflow "
            f"events_total={events_total}i,parsed_events_total={parsed_events_total}i,"
            f"entry_events_total={entry_events_total}i,return_events_total={return_events_total}i,"
            f"unparsed_events_total={unparsed_events_total}i,folded_stacks_total={len(folded)}i,"
            f"max_depth={max_depth}i,available={available},first_ts_ns={first_ts_ns}i {ts}\n"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
