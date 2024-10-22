#!/bin/bash
is_desktop=1
is_dell_laptop=0
echo "Setting CPU to Performance mode..."
echo

# set teo idle cpu governor
echo "Set CPU idle governor to TEO"
echo teo > /sys/devices/system/cpu/cpuidle/current_governor
echo

# check if running on laptop or desktop
if [[ `lshw|grep -m1 description|awk '{print $2}'` != 'Desktop' ]];then
  is_desktop=0
  echo "Running on a laptop..."
  if [[ `lshw|grep -m1 vendor|awk '{print $2}'` == 'Dell' ]];then
    echo "Dell laptop detected"
    echo
    is_dell_laptop=1
  fi
fi

if [[ $is_dell_laptop == 1 ]];then
  echo "Setting Dell smbios thermal control to performance mode"
  # set smbios thermal control
  smbios-thermal-ctl --set-thermal-mode=Performance
  echo
fi

# set power bias
echo "Setting CPU energy bias to 0"
cpupower set -b 0
echo

# set cpu to performance mode
echo "Setting CPU to performance mode"
cpupower frequency-set -g performance
echo

if [[ $is_dell_laptop == 1 ]];then
  # limit CPU to 3900MHz
  echo "Limiting Dell laptop CPU to 3.9GHz"
  cpupower frequency-set -u 3900000
  echo
fi

# set idle mode
echo "Setting CPU to C1 state"
cpupower idle-set -D 10
echo

echo "Finished setting CPU to Performance mode."
