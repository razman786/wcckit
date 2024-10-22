#!/bin/bash
is_desktop=1
is_dell_laptop=0
echo "Resetting CPU to Normal mode..."
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

# set cpu to schedutil mode
echo "Resetting CPU to Schedutil mode"
cpupower frequency-set -g schedutil
echo

# set idle mode
echo "Re-enabling all CPU C-States"
cpupower idle-set -E
echo

if [[ $is_dell_laptop == 1 ]];then
  # reset CPU to 4.5GHz
  echo "Resetting Dell laptop CPU to 4.5GHz"
  cpupower frequency-set -u 4500000
  echo
fi

# set power bias - default seems to be 0
echo "Resetting CPU energy bias to 0"
cpupower set -b 0
echo

if [[ $is_dell_laptop == 1 ]];then
  echo "Setting Dell smbios thermal control to balanced mode"
  # reset smbios 
  smbios-thermal-ctl --set-thermal-mode=Balanced
  echo
fi

echo "Finished resetting CPU to Normal mode."
