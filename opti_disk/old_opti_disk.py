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
#

import subprocess


class OptiDisk():

    def __init__(self):
        super(OptiDisk, self).__init__()
        self.load_opti_disk()

    def load_opti_disk(self):
        self.check_config()

    def check_config(self):
        try:
            process_output = subprocess.run(['./config_nvme_queues.sh', '-d'],
                                            stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT,
                                            bufsize=1,
                                            text=True,
                                            check=True,
                                            universal_newlines=True)
        except subprocess.CalledProcessError:
            print("Error detected while executing the command")
        except Exception as e:
            print(f"Error detected while executing the command: {e}")
        else:
            if process_output.returncode == 0:
                print(process_output.stdout)
            else:
                print("foobar")

    # def check_config_alt(self):
    #     try:
    #         with subprocess.Popen(["locatemenot", "a"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1, universal_newlines=True) as p:
    #             for line in p.stdout:
    #                 print(line, end='') # process line here
    #     except subprocess.CalledProcessError:
    #         print("Error detected while executing the command")

    #     if p.returncode != 0:
    #         raise subprocess.CalledProcessError(p.returncode, p.args)

if __name__ == '__main__':
    opti_disk = OptiDisk()
