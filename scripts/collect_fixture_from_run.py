#!/usr/bin/env python3
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
"""Promote small redacted WCCKIT run artifacts into parser fixtures.

The script copies selected raw/derived artifacts from a ``runs/<run_id>/``
directory into a fixture output directory and writes metadata alongside them.
It is intentionally conservative: files are size-limited, obvious host-specific
values are redacted, and existing fixtures are not overwritten unless requested.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import socket
import sys
import time
from pathlib import Path
from typing import Iterable

COLLECTOR_PATTERNS: dict[str, tuple[str, ...]] = {
    "bpf-io": (
        "logs/bpf.log",
        "events/bpf-io.jsonl",
        "metrics/bpf-io.lp",
    ),
    "app-uflow": (
        "events/app-uflow.raw.log",
        "events/app-uflow.jsonl",
        "profiles/app-uflow.folded",
        "metrics/app-uflow.lp",
        "logs/app.log",
    ),
    "app-ucalls": (
        "events/app-ucalls.jsonl",
        "metrics/app-ucalls.lp",
        "logs/app.log",
    ),
    "app-ustat": (
        "events/app-ustat.jsonl",
        "metrics/app-ustat.lp",
        "logs/app.log",
    ),
    "amd-uprof-pcm": (
        "events/amd-uprof-pcm.csv",
        "events/amd-uprof-pcm.jsonl",
        "metrics/amd-uprof-pcm.lp",
        "logs/amd-uprof-pcm.log",
    ),
    "amd-uprof-memory": (
        "events/amd-uprof-memory.csv",
        "events/amd-uprof-memory.jsonl",
        "metrics/amd-uprof-memory.lp",
        "logs/amd-uprof-memory.log",
    ),
    "amd-uprof-power": (
        "events/amd-uprof-power.csv",
        "events/amd-uprof-power.jsonl",
        "metrics/amd-uprof-power.lp",
        "logs/amd-uprof-power.log",
    ),
    "amd-esmi-energy": (
        "events/amd-esmi-energy.csv",
        "events/amd-esmi-energy.jsonl",
        "metrics/amd-esmi-energy.lp",
        "logs/amd-esmi-energy.log",
    ),
    "intel-pcm": (
        "events/pcm.jsonl",
        "metrics/pcm.lp",
        "logs/pcm.log",
        "logs/pcm.status",
    ),
    "roofline": (
        "events/amd-uprof-roofline.jsonl",
        "metrics/amd-uprof-roofline.lp",
        "roofline/amd-uprof/manifest.json",
        "logs/amd-uprof-roofline.log",
    ),
    "manifest": ("manifest.json",),
}

TEXT_EXTENSIONS = {
    ".csv", ".json", ".jsonl", ".log", ".lp", ".txt", ".tsv", ".folded", ".status"
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_label(value: str) -> str:
    label = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip()).strip(".-")
    return label or "fixture"


def selected_paths(run_dir: Path, collector: str) -> list[Path]:
    if collector == "all":
        names: list[str] = []
        for key in sorted(COLLECTOR_PATTERNS):
            names.extend(COLLECTOR_PATTERNS[key])
    else:
        names = list(COLLECTOR_PATTERNS[collector])
    paths: list[Path] = []
    seen: set[Path] = set()
    for name in names:
        path = run_dir / name
        if path.exists() and path.is_file() and path not in seen:
            paths.append(path)
            seen.add(path)
    return paths


def redact_text(text: str, extra_patterns: Iterable[str]) -> str:
    replacements = [
        (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "<IP>"),
        (re.compile(r"/home/[A-Za-z0-9_.-]+"), "/home/<USER>"),
        (re.compile(r"/Users/[A-Za-z0-9_.-]+"), "/Users/<USER>"),
        (re.compile(r"/tmp/[A-Za-z0-9_.:/-]+"), "/tmp/<PATH>"),
        (re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "<EMAIL>"),
    ]
    try:
        host = socket.gethostname()
        if host:
            replacements.append((re.compile(re.escape(host)), "<HOST>"))
    except Exception:
        pass
    user = os.environ.get("USER") or os.environ.get("USERNAME")
    if user:
        replacements.append((re.compile(rf"\b{re.escape(user)}\b"), "<USER>"))
    for pattern in extra_patterns:
        if pattern:
            replacements.append((re.compile(pattern), "<REDACTED>"))
    for pattern, repl in replacements:
        text = pattern.sub(repl, text)
    return text


def read_limited(path: Path, max_bytes: int) -> tuple[bytes, bool]:
    data = path.read_bytes()
    if len(data) <= max_bytes:
        return data, False
    marker = f"\n<WCCKIT_FIXTURE_TRUNCATED original_bytes={len(data)} kept_bytes={max_bytes}>\n".encode()
    return data[:max_bytes] + marker, True


def write_fixture_file(source: Path, dest: Path, max_bytes: int, extra_redactions: list[str]) -> dict[str, object]:
    original = source.read_bytes()
    limited, truncated = read_limited(source, max_bytes)
    redacted = False
    if source.suffix.lower() in TEXT_EXTENSIONS:
        text = limited.decode("utf-8", "replace")
        redacted_text = redact_text(text, extra_redactions)
        redacted = redacted_text != text
        output = redacted_text.encode("utf-8")
    else:
        output = limited
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(output)
    return {
        "source": str(source),
        "fixture": str(dest),
        "source_bytes": len(original),
        "fixture_bytes": len(output),
        "truncated": truncated,
        "redacted": redacted,
        "source_sha256": sha256_bytes(original),
        "fixture_sha256": sha256_bytes(output),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect redacted WCCKIT parser fixtures from a run directory")
    parser.add_argument("--run", required=True, type=Path, help="Path to runs/<run_id> directory")
    parser.add_argument("--collector", required=True, choices=sorted([*COLLECTOR_PATTERNS, "all"]))
    parser.add_argument("--output", default=Path("tests/fixtures/captured"), type=Path)
    parser.add_argument("--label", help="Fixture set label. Default: <run-dir-name>-<collector>")
    parser.add_argument("--max-bytes", default=65536, type=int, help="Maximum bytes copied per source file before truncation")
    parser.add_argument("--redact-regex", action="append", default=[], help="Additional regex to redact from text fixtures")
    parser.add_argument("--force", action="store_true", help="Overwrite an existing fixture set")
    args = parser.parse_args()

    if not args.run.is_dir():
        print(f"run directory not found: {args.run}", file=sys.stderr)
        return 2
    if args.max_bytes < 256:
        print("--max-bytes must be at least 256", file=sys.stderr)
        return 2

    label = safe_label(args.label or f"{args.run.name}-{args.collector}")
    dest_root = args.output / label
    if dest_root.exists() and not args.force:
        print(f"fixture output already exists: {dest_root}; use --force to overwrite", file=sys.stderr)
        return 2
    dest_root.mkdir(parents=True, exist_ok=True)

    paths = selected_paths(args.run, args.collector)
    if not paths:
        print(f"no known files found for collector {args.collector!r} in {args.run}", file=sys.stderr)
        return 1

    files = []
    for source in paths:
        relative = source.relative_to(args.run)
        dest = dest_root / relative
        files.append(write_fixture_file(source, dest, args.max_bytes, args.redact_regex))

    metadata = {
        "schema": "wcckit.fixture_capture.v1",
        "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "run_dir": str(args.run),
        "run_id": args.run.name,
        "collector": args.collector,
        "label": label,
        "redacted": True,
        "max_bytes_per_file": args.max_bytes,
        "files": files,
        "notes": [
            "Review fixtures before committing.",
            "Keep only small representative samples and remove sensitive project data.",
            "Raw run directories remain the canonical local archive.",
        ],
    }
    meta_path = dest_root / "fixture.meta.json"
    meta_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    print(f"wrote {len(files)} fixture file(s) to {dest_root}")
    print(f"metadata: {meta_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
