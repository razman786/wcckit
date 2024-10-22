#!/bin/bash

# declare defaults
run_test=""
timeouts=10
nvme_dev="/dev/nvme0n1"
check_sensor_2=""
second_temp=""
#fio_args="--output-format=json"
fio_args=""

run_fio(){
    echo "Starting FIO tests..."
    echo 

    # Get CPU list
    cpu_list=`lscpu| grep 'On-line CPU'|awk '{print $4}'`
    cpu_list=${cpu_list//[0]/1}

    # Take temp, run, wait for temp before continuing 
    echo "Gathering CPU and NVMe temperatures:"
    echo

    # check for multiple sensors
    check_sensor_1=`nvme smart-log ${nvme_dev} |grep 'Temperature Sensor 1'|awk '{print $5}'`
    if [[ -z "$check_sensor_1" ]];then
        echo "NVMe does not contain more than 1 sensor, defaulting to single reading."
        echo
        first_temp=`nvme smart-log ${nvme_dev}|grep temperature|awk '{print $3}'`
    else
        echo "NVMe contains temperature sensor 1, checking for sensor 2..."
        echo
        check_sensor_2=`nvme smart-log ${nvme_dev} |grep 'Temperature Sensor 2'|awk '{print $5}'`
        if [[ -z "$check_sensor_2" ]];then
            echo "NVMe does not contain more than 1 sensor, defaulting to single reading."
            echo
            first_temp=`nvme smart-log ${nvme_dev}|grep temperature|awk '{print $3}'`
        else
            echo "NVMe contains 2 sensors."
            echo
            first_temp=`nvme smart-log ${nvme_dev} |grep 'Temperature Sensor 1'|awk '{print $5}'`
            second_temp=`nvme smart-log ${nvme_dev} |grep 'Temperature Sensor 2'|awk '{print $5}'`
        fi
    fi

    # get CPU temp
    first_cpu_temp=`sensors -u|grep -A1 'Package id 0'|grep temp1_input|awk '{print int($2)}'`
    echo "CPU base temp ${first_cpu_temp}C"
    declare -i cpu_temp_buffer=2
    echo "Adding ${cpu_temp_buffer}C to CPU base temp"
    first_cpu_temp="$((first_cpu_temp+cpu_temp_buffer))"
    echo "CPU adjusted base temp ${first_cpu_temp}C"
    echo
    
    # get NVMe temp 1
    echo "NVMe base temp ${first_temp}C"
    # let ten_percent=first_temp/10 # old plus 10% might be too much
    declare -i ten_percent=2
    echo "Adding ${ten_percent}C to base temp"
    first_temp="$((first_temp+ten_percent))"
    echo "NVMe adjusted base temp ${first_temp}C"
    echo

    # if second sensors then adjust base temp
    if [[ -n "$second_temp" ]];then
        echo "NVMe second base temp ${second_temp}C"
        echo "Adding ${ten_percent}C to second base temp"
        second_temp="$((second_temp+ten_percent))"
        echo "NVMe adjusted second base temp ${second_temp}C"
        echo
    fi
}

exec_temp_1(){
    if [[ -n "$second_temp" ]];then
        echo `nvme smart-log ${nvme_dev} |grep 'Temperature Sensor 1'|awk '{print $5}'`
    else
        echo `nvme smart-log ${nvme_dev}|grep temperature|awk '{print $3}'`
    fi
}

exec_temp_2(){
    echo `nvme smart-log ${nvme_dev} |grep 'Temperature Sensor 2'|awk '{print $5}'`
}

exec_cpu_temp(){
    echo `sensors -u|grep -A1 'Package id 0'|grep temp1_input|awk '{print int($2)}'`
}

check_temp() {
  # check NVMe temp
  while [ $first_temp -lt $(exec_temp_1) ]
  do
    echo -ne "Waiting for current NVMe temp $(exec_temp_1)C to be below base temp ${first_temp}C and CPU current temp $(exec_cpu_temp)C to be below CPU base temp ${first_cpu_temp}C\\r"
    sleep 3
  done
  # check NVMe temp 2
  if [[ -n "$second_temp" ]];then
      while [ $second_temp -lt $(exec_temp_2) ]
      do
        echo -ne "Waiting for second NVMe temp $(exec_temp_2)C to be below base temp ${second_temp}C and CPU current temp $(exec_cpu_temp)C to be below CPU base temp ${first_cpu_temp}C\\r"
        sleep 3
      done
  fi
  # check CPU temp
  while [ $first_cpu_temp -lt $(exec_cpu_temp) ]
  do
    echo -ne "Waiting for current NVMe temp $(exec_temp_1)C to be below base temp ${first_temp}C and CPU current temp $(exec_cpu_temp)C to be below CPU base temp ${first_cpu_temp}C\\r"
    sleep 3
  done
  # final output
  echo -ne "Waiting for current NVMe temp $(exec_temp_1)C to be below base temp ${first_temp}C and CPU current temp $(exec_cpu_temp)C to be below CPU base temp ${first_cpu_temp}C\\r"
  if [[ -n "$second_temp" ]];then
      echo
      echo -ne "Waiting for second NVMe temp $(exec_temp_2)C to be below base temp ${second_temp}C and CPU current temp $(exec_cpu_temp)C to be below CPU base temp ${first_cpu_temp}C\\r"
  fi
  echo
}

flush_disk(){
    echo
    echo "Flushing disk caches..."
    sync;echo 3 > /proc/sys/vm/drop_caches;hdparm -f /dev/${nvme_dev} 2>/dev/null 1>&2 ;nvme flush /dev/${nvme_dev} 2>/dev/null 1>&2
}

exec_seq(){
    seq_write
    seq_read
}

exec_rand(){
    rand_write
    rand_read
    rand_rw
}

run_all(){
    run_fio
    setup_test
    exec_seq
    exec_rand
}

run_seq(){
    run_fio
    setup_test
    exec_seq
}

run_rand(){
    run_fio
    setup_test
    exec_rand
}

run_writes(){
    run_fio
    setup_test
    seq_write
    rand_write
}

run_reads(){
    run_fio
    setup_test
    seq_read
    rand_read
}

run_selected(){
    if [ $run_test == "seq" ];then
        run_seq
    elif [ $run_test == "rand" ];then
        run_rand
    elif [ $run_test == "writes" ];then
        run_writes
    elif [ $run_test == "reads" ];then
        run_reads
    else
        run_all
    fi
}

setup_test(){
    echo "Creating test file..."
    CPULIST=$cpu_list fio write.fio --create_only=1
    flush_disk
    check_temp
    echo "Pausing for 30 secs..."
    echo
    sleep 30
    echo "FIO testing started..."
    echo
}

seq_write(){
    echo "Write 2048k"
    CPULIST=$cpu_list fio write.fio --output=opti_write.log $fio_args
    flush_disk
    check_temp
    echo "Pausing for $timeouts secs..."
    echo
    sleep $timeouts
}

seq_read(){
    echo "Read 2048k"
    CPULIST=$cpu_list fio read.fio --output=opti_read.log $fio_args
    flush_disk
    check_temp
    echo "Pausing for $timeouts secs..."
    echo
    sleep $timeouts
}

rand_write(){
    echo "Random Write 4k"
    CPULIST=$cpu_list fio randomwrite.fio --output=opti_randwrite.log $fio_args
    flush_disk
    check_temp
    echo "Pausing for $timeouts secs..."
    echo
    sleep $timeouts
}

rand_read(){
    echo "Random Read 4k"
    CPULIST=$cpu_list fio randomread.fio --output=opti_randread.log $fio_args
    flush_disk
    check_temp
    echo "Pausing for $timeouts secs..."
    echo
    sleep $timeouts
}

rand_rw(){
    echo "Random Read/Write 4k"
    CPULIST=$cpu_list fio randomrw.fio --output=opti_randrw.log $fio_args
    flush_disk
    check_temp
    echo "Pausing for $timeouts secs..."
    echo
    sleep $timeouts
}

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "Run FIO to test NVMe devices."
   echo
   echo "Syntax: run_fio.sh [-h|-t|-o]"
   echo "options:"
   echo "-h         Print this Help."
   echo "-t         Select test to run (seq|rand|writes|reads)."
   echo "-o         Disable JSON log output."
   echo
}

# Get the options
if [ $# -ne 0 ];then
    while getopts ':t:h' option; do
        case $option in
            h) # display Help
               Help
               exit;;
            t) # exec selected tests
               echo "Running selected test (${OPTARG})..."
               echo
               run_test=$OPTARG
               run_selected;;
            \?) # Invalid option
                echo "Error: Invalid option"
                Help
                exit;;
        esac
    done
else
    echo "Running all tests (Default)..."
    echo
    run_all
fi
