#!/usr/bin/env python3
#  Copyright (c) 2022, Dr Rahim Lakhoo, razman786@gmail.com.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.
#

import subprocess
from prompt_toolkit import prompt
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit import Application
from prompt_toolkit.shortcuts import message_dialog
from prompt_toolkit.buffer import Buffer
from prompt_toolkit.layout.containers import VSplit, Window
from prompt_toolkit.layout.controls import BufferControl, FormattedTextControl
from prompt_toolkit.layout.layout import Layout

class OptiDisk():

    def __init__(self):
        super(OptiDisk, self).__init__()
        self.choice = None
        self.output = None
        self.layout = None
        self.buffer1 = None
        self.load_opti_disk()

    def load_opti_disk(self):
        # TODO - add method for interaction (menu)
        self.setup_layout()
        self.main_menu()

    def setup_layout(self):
        self.buffer1 = Buffer()  # Editable buffer.

        root_container = VSplit([
            # One window that holds the BufferControl with the default buffer on
            # the left.
            Window(content=BufferControl(buffer=self.buffer1)),

            # A vertical line in the middle. We explicitly specify the width, to
            # make sure that the layout engine will not try to divide the whole
            # width by three for all these windows. The window will simply fill its
            # content by repeating this character.
            Window(width=1, char='|'),

            # Display the text 'Hello world' on the right.
            Window(content=self.main_menu()),
        ])

        self.layout = Layout(root_container)

    def main_menu(self):
        app = Application(layout=self.layout, full_screen=True)
        app.run()
        print("Welcome to Opti Disk, part of WCCKIT (Workload Characterisation and Capacity Kit)\n")
        first_menu = WordCompleter(['Setup NVMe Device', 'Configure NVMe Queues', 'Set CPU Mode', 'Reset CPU Mode', 'Run FIO'])
        self.choice = prompt('Please select a task: ', completer=first_menu)
        print(f"Option selected is {self.choice}")
        if self.choice == 'Configure NVMe Queues':
            self.config_nvme_queues()


    def execute(self, command):
        try:
            process_output = subprocess.run(command,
                                            stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT,
                                            bufsize=1,
                                            text=True,
                                            check=True,
                                            universal_newlines=True)
        except subprocess.CalledProcessError:
            print("Subprocess called error detected while executing the command")
        except Exception as e:
            print(f"Error detected while executing the command: {e}")
        else:
            if process_output.returncode == 0:
                print(process_output.stdout)
                return process_output.stdout
            else:
                print(f"Subprocess return code is non zero {process_output.returncode}")
                return None

    def config_nvme_queues(self):
        # config polling and write queues
        #command = ["./config_nvme_queues.sh", "-p", "-w", "-d"]
        command = ["./config_nvme_queues.sh", "-d"]
        self.output = self.execute(command)

        if "Finished configuration for NVMe queues" not in self.output:
            print("Error: config_nvme_queues")
        else:
            Window(content=self.show_message())
            self.main_menu()

    def show_message(self):
        message_dialog(
            title=self.choice,
            text=self.output).run()


if __name__ == '__main__':

    opti_disk = OptiDisk()
