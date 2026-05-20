#!/usr/bin/env python3
# Copyright (c) 2026, Dr Rahim Lakhoo.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic Python hotspot for validating WCCKIT PID profiling.

This script intentionally burns CPU in a named function so the WCCKIT Docker
profiler has a stable target. Run it with ``python3 -X perf`` where supported so
native profilers have a better chance of resolving Python function names.
"""

from __future__ import annotations

import argparse
import inspect
import math
import os
import signal
import sys
import time


STOP = False


def handle_stop(signum: int, frame: object) -> None:
    del signum, frame
    global STOP
    STOP = True


def wcckit_intentional_hotspot(channels: int, baselines: int) -> float:
    """Deliberately expensive stand-in for a repeated pipeline kernel."""
    total = 0.0
    for channel in range(channels):
        phase = channel * 0.0001220703125
        for baseline in range(baselines):
            total += math.sin(phase + baseline) * math.cos(phase - baseline)  # WCCKIT_HOTSPOT
    return total


def hotspot_line() -> int:
    source_lines, first_line = inspect.getsourcelines(wcckit_intentional_hotspot)
    for offset, line in enumerate(source_lines):
        if "WCCKIT_HOTSPOT" in line:
            return first_line + offset
    return first_line


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a CPU-heavy Python loop for WCCKIT profiler validation."
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=120.0,
        help="seconds to run; use 0 to run until interrupted",
    )
    parser.add_argument("--channels", type=int, default=384)
    parser.add_argument("--baselines", type=int, default=256)
    parser.add_argument("--report-interval", type=float, default=5.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.channels <= 0 or args.baselines <= 0:
        print("channels and baselines must be positive", file=sys.stderr)
        return 2

    signal.signal(signal.SIGTERM, handle_stop)
    signal.signal(signal.SIGINT, handle_stop)

    script_path = os.path.abspath(__file__)
    line_number = hotspot_line()
    deadline = None if args.duration == 0 else time.monotonic() + args.duration
    next_report = time.monotonic()
    iterations = 0
    checksum = 0.0

    print(f"PID={os.getpid()}", flush=True)
    print(f"HOTSPOT={script_path}:{line_number}", flush=True)
    print("HOTSPOT_FUNCTION=wcckit_intentional_hotspot", flush=True)
    print(
        "Profiler command example: "
        "dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- "
        f"wcckit_profile_cpu.sh --pid {os.getpid()} "
        "--duration 15 --frequency 99 --output /out/python-hotspot.svg",
        flush=True,
    )

    while not STOP:
        checksum += wcckit_intentional_hotspot(args.channels, args.baselines)
        iterations += 1
        now = time.monotonic()
        if now >= next_report:
            print(
                f"iterations={iterations} checksum={checksum:.6f}",
                flush=True,
            )
            next_report = now + args.report_interval
        if deadline is not None and now >= deadline:
            break

    print(f"done iterations={iterations} checksum={checksum:.6f}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
