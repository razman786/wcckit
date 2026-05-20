#!/usr/bin/env python3
#  Copyright (c) 2022, Raz, razman786@users.noreply.github.com.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License version 2 as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

"""Prompt-based Opti-Disk control menu.

Opti-Disk is the disk-focused WCCKIT subset for characterising NVMe speed and
configuration efficiency for radio-astronomy style processing pipelines. The UI
keeps destructive operations explicit and leaves final confirmation to the shell
scripts that perform hardware-affecting work.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from prompt_toolkit import prompt
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit.shortcuts import message_dialog, radiolist_dialog, yes_no_dialog


class OptiDisk:
    MENU_OPTIONS = [
        ("display_nvme", "Display NVMe queue configuration"),
        ("configure_nvme_dry", "Preview NVMe queue config command"),
        ("setup_nvme_dry", "Dry-run NVMe device setup"),
        ("run_fio_dry", "Dry-run fio workflow"),
        ("configure_nvme_real", "Configure NVMe queues for real"),
        ("set_cpu_real", "Set CPU performance mode for real"),
        ("reset_cpu_real", "Reset CPU normal mode for real"),
        ("run_fio_real", "Run fio workflow for real"),
        ("quit", "Quit"),
    ]

    TEST_OPTIONS = ["all", "seq", "rand", "writes", "reads"]

    def __init__(self, script_dir: Path | None = None) -> None:
        self.script_dir = script_dir or Path(__file__).resolve().parent
        self.fio_dir = self.script_dir / "fio_scripts"

    def run(self) -> int:
        print("Opti-Disk - WCCKIT disk speed and efficiency characterisation")
        print("Default actions are dry-run or display-only. Real hardware actions require confirmation.\n")

        while True:
            selected = self.select_menu_option()
            if selected in (None, "quit"):
                return 0

            try:
                self.handle_choice(selected)
            except KeyboardInterrupt:
                print("\nCancelled.")
            except subprocess.CalledProcessError as exc:
                print(f"Command failed with exit code {exc.returncode}: {' '.join(exc.cmd)}", file=sys.stderr)
            except RuntimeError as exc:
                print(f"Error: {exc}", file=sys.stderr)

            print()

    def select_menu_option(self) -> str | None:
        return radiolist_dialog(
            title="Opti-Disk",
            text="Select a task",
            values=self.MENU_OPTIONS,
        ).run()

    def handle_choice(self, choice: str) -> None:
        if choice == "display_nvme":
            self.execute([self.script_dir / "config_nvme_queues.sh", "-d"])
        elif choice == "configure_nvme_dry":
            print("Preview: ./config_nvme_queues.sh -p -w -d")
            print("This writes only the local opti_disk/nvme.conf unless -i is used.")
        elif choice == "setup_nvme_dry":
            device = self.ask_device()
            self.execute([self.script_dir / "set_nvme.sh", "--dry-run", "--device", device])
        elif choice == "run_fio_dry":
            device = self.ask_device(default="/dev/nvme0n1")
            test = self.ask_test()
            self.execute([self.fio_dir / "run_fio.sh", "--dry-run", "--device", device, "--test", test])
        elif choice == "configure_nvme_real":
            self.confirm_real_action("configure NVMe queue options")
            self.execute([self.script_dir / "config_nvme_queues.sh", "-p", "-w", "-i", "-d"])
        elif choice == "set_cpu_real":
            self.confirm_real_action("set CPU performance mode")
            self.execute([self.script_dir / "set_cpu_mode.sh"])
        elif choice == "reset_cpu_real":
            self.confirm_real_action("reset CPU normal mode")
            self.execute([self.script_dir / "reset_cpu_mode.sh"])
        elif choice == "run_fio_real":
            device = self.ask_device(default="/dev/nvme0n1")
            test = self.ask_test()
            self.confirm_real_action(f"run fio {test} workload on {device}")
            self.execute([self.fio_dir / "run_fio.sh", "--device", device, "--test", test])
        else:
            raise RuntimeError(f"unknown menu choice: {choice}")

    def ask_device(self, default: str = "/dev/nvme0n1") -> str:
        device = prompt("Target NVMe device: ", default=default).strip()
        if not device:
            raise RuntimeError("device is required")
        return device

    def ask_test(self) -> str:
        completer = WordCompleter(self.TEST_OPTIONS, ignore_case=True)
        test = prompt("fio test [all|seq|rand|writes|reads]: ", default="all", completer=completer).strip()
        if test not in self.TEST_OPTIONS:
            raise RuntimeError(f"invalid fio test '{test}'")
        return test

    def confirm_real_action(self, action: str) -> None:
        confirmed = yes_no_dialog(
            title="Confirm real hardware action",
            text=(
                f"This will {action}. It may change system state or run a real benchmark.\n\n"
                "Continue?"
            ),
        ).run()
        if not confirmed:
            raise RuntimeError("real action was not confirmed")

    def execute(self, command: Sequence[Path | str]) -> str:
        cmd = [str(part) for part in command]
        print(f"Running: {' '.join(cmd)}")
        process = subprocess.run(
            cmd,
            cwd=self.script_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=True,
        )
        output = process.stdout or "Command completed with no output."
        self.show_output("Command output", f"$ {' '.join(cmd)}\n\n{output}")
        return output

    def show_output(self, title: str, text: str) -> None:
        # Display command output in the foreground; printing alone is hidden
        # behind prompt_toolkit dialogs in many terminals.
        message_dialog(title=title, text=text).run()
        print(text)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Opti-Disk prompt menu")
    parser.add_argument(
        "--script-dir",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Directory containing opti_disk shell scripts.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    return OptiDisk(args.script_dir).run()


if __name__ == "__main__":
    raise SystemExit(main())
