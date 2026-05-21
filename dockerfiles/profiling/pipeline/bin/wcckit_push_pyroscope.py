#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Push a folded stack profile to Grafana Pyroscope.

WCCKIT keeps folded stacks as local reproducible artifacts. For interactive
Grafana/Pyroscope views, this helper converts folded stacks to a minimal pprof
profile and sends it through Pyroscope's current Push API. This avoids the
legacy folded /ingest path, which can index labels but return zero samples on
current Pyroscope releases.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


PROFILE_TYPE_ID = "process_cpu:samples:count:cpu:nanoseconds"


def clean_app_name(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.:-]+", "_", value.strip())
    return value or "wcckit"


def label_value(value: object) -> str:
    value = re.sub(r"[^A-Za-z0-9_.:-]+", "_", str(value).strip())
    return value or "unknown"


def timestamp_ns(ns_value: str | None, fallback: int) -> int:
    if not ns_value:
        return fallback
    try:
        return max(0, int(ns_value))
    except ValueError as exc:
        raise SystemExit(f"invalid nanosecond timestamp: {ns_value}") from exc


def encode_varint(value: int) -> bytes:
    value = int(value)
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def proto_key(field: int, wire_type: int) -> bytes:
    return encode_varint((field << 3) | wire_type)


def proto_int(field: int, value: int) -> bytes:
    return proto_key(field, 0) + encode_varint(value)


def proto_msg(field: int, payload: bytes) -> bytes:
    return proto_key(field, 2) + encode_varint(len(payload)) + payload


def proto_string(field: int, value: str) -> bytes:
    data = value.encode("utf-8")
    return proto_key(field, 2) + encode_varint(len(data)) + data


def value_type(type_index: int, unit_index: int) -> bytes:
    return proto_int(1, type_index) + proto_int(2, unit_index)


def line(function_id: int) -> bytes:
    return proto_int(1, function_id)


def function(function_id: int, name_index: int) -> bytes:
    return (
        proto_int(1, function_id)
        + proto_int(2, name_index)
        + proto_int(3, name_index)
    )


def location(location_id: int, function_id: int) -> bytes:
    return proto_int(1, location_id) + proto_msg(4, line(function_id))


def sample(location_ids: list[int], count: int) -> bytes:
    payload = b"".join(proto_int(1, loc_id) for loc_id in location_ids)
    payload += proto_int(2, count)
    return payload


def parse_folded(path: Path) -> list[tuple[list[str], int]]:
    rows: list[tuple[list[str], int]] = []
    for line_no, raw in enumerate(path.read_text(errors="replace").splitlines(), start=1):
        line_text = raw.strip()
        if not line_text:
            continue
        try:
            stack_text, count_text = line_text.rsplit(None, 1)
            count = int(float(count_text))
        except ValueError:
            print(f"skipping malformed folded line {line_no}: {raw}", file=sys.stderr)
            continue
        if count <= 0:
            continue
        stack = [part.strip() or "unknown" for part in stack_text.split(";")]
        if stack and stack[0] == "total":
            stack = stack[1:]
        if stack:
            rows.append((stack, count))
    return rows


def folded_to_pprof(rows: list[tuple[list[str], int]], start_ns: int, duration_ns: int) -> bytes:
    strings = ["", "samples", "count", "cpu", "nanoseconds"]
    string_ids = {value: idx for idx, value in enumerate(strings)}

    def intern(value: str) -> int:
        if value not in string_ids:
            string_ids[value] = len(strings)
            strings.append(value)
        return string_ids[value]

    symbol_ids: dict[str, int] = {}

    def symbol_id(symbol: str) -> int:
        if symbol not in symbol_ids:
            symbol_ids[symbol] = len(symbol_ids) + 1
            intern(symbol)
        return symbol_ids[symbol]

    for stack, _count in rows:
        for symbol in stack:
            symbol_id(symbol)

    profile = b""
    profile += proto_msg(1, value_type(string_ids["samples"], string_ids["count"]))

    for stack, count in rows:
        # Folded stacks are root-to-leaf; pprof location_id order is leaf-to-root.
        loc_ids = [symbol_id(symbol) for symbol in reversed(stack)]
        profile += proto_msg(2, sample(loc_ids, count))

    for symbol, loc_id in sorted(symbol_ids.items(), key=lambda item: item[1]):
        profile += proto_msg(4, location(loc_id, loc_id))
    for symbol, func_id in sorted(symbol_ids.items(), key=lambda item: item[1]):
        profile += proto_msg(5, function(func_id, string_ids[symbol]))
    for value in strings:
        profile += proto_string(6, value)

    profile += proto_int(9, start_ns)
    profile += proto_int(10, max(1, duration_ns))
    profile += proto_msg(11, value_type(string_ids["cpu"], string_ids["nanoseconds"]))
    profile += proto_int(12, 10_000_000)
    profile += proto_int(14, 0)
    return gzip.compress(profile)


def push_pprof(url: str, app_name: str, profile_type: str, pprof_gz: bytes, run_id: str, pipeline: str, pid: str) -> None:
    labels = [
        {"name": "__name__", "value": "process_cpu"},
        {"name": "service_name", "value": clean_app_name(app_name)},
        {"name": "run_id", "value": label_value(run_id)},
        {"name": "pipeline", "value": label_value(pipeline)},
        {"name": "pid", "value": label_value(pid)},
        {"name": "profile_type", "value": label_value(profile_type)},
    ]
    body = {
        "series": [
            {
                "labels": labels,
                "samples": [
                    {
                        "ID": str(uuid.uuid4()),
                        "rawProfile": base64.b64encode(pprof_gz).decode("ascii"),
                    }
                ],
            }
        ]
    }
    req = urllib.request.Request(
        f"{url.rstrip('/')}/push.v1.PusherService/Push",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        payload = response.read().decode("utf-8", "replace")
        if response.status >= 300:
            raise RuntimeError(f"HTTP {response.status}: {payload}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Push WCCKIT folded profiles to Pyroscope")
    parser.add_argument("--url", required=True, help="Pyroscope URL, for example http://127.0.0.1:4040")
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--profile-type", required=True, choices=["cpu", "uflow"])
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--pipeline", required=True)
    parser.add_argument("--pid", required=True)
    parser.add_argument("--from-timestamp-ns")
    parser.add_argument("--until-timestamp-ns")
    args = parser.parse_args()

    if not args.input.exists() or args.input.stat().st_size == 0:
        print(f"folded profile is missing or empty: {args.input}", file=sys.stderr)
        return 2

    now_ns = time.time_ns()
    until_ns = timestamp_ns(args.until_timestamp_ns, now_ns)
    start_ns = timestamp_ns(args.from_timestamp_ns, max(0, until_ns - 10_000_000_000))
    if until_ns <= start_ns:
        until_ns = start_ns + 1

    rows = parse_folded(args.input)
    if not rows:
        print(f"folded profile has no valid samples: {args.input}", file=sys.stderr)
        return 2

    pprof_gz = folded_to_pprof(rows, start_ns, until_ns - start_ns)
    try:
        push_pprof(args.url, args.app_name, args.profile_type, pprof_gz, args.run_id, args.pipeline, args.pid)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        print(f"Pyroscope push failed: HTTP {exc.code}: {body}", file=sys.stderr)
        return 1
    except urllib.error.URLError as exc:
        print(f"Pyroscope push failed: {exc}", file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(f"Pyroscope push failed: {exc}", file=sys.stderr)
        return 1

    print(f"pushed {args.profile_type} folded profile to {args.url.rstrip('/')} as {PROFILE_TYPE_ID}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
