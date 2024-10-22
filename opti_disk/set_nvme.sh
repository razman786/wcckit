#!/bin/bash
############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "Setup NVMe devices for testing."
   echo
   echo "Syntax: set_nvme.sh [-h|-d|-m|-l|-s]"
   echo "options:"
   echo "-h     Print this Help."
   echo "-d     Set NVMe device (i.e. nvme0n1)."
   echo "-m     Set mount point (i.e. nvme)."
   echo "-l     Override NVMe auto LBA 4KB support (i.e. 1)."
   echo "-s     Set NVMe partition sector alignment (i.e. 8192)."
   echo
}

echo "Starting NVMe device setup."
echo

# declare defaults
mnt_point="nvme"
nvme_dev=""
is_4k_lba=0
override_4k_lba=0
sector_size=2048 # samsung pro 8192

# Get the options
while getopts ':d:m:s:l:h' option; do
    case $option in
        h) # display Help
           Help
           exit;;
        d) # set NVMe device
           nvme_dev=$OPTARG
           echo "NVMe device set as /dev/$nvme_dev";;
        m) # set mount point
           mnt_point=$OPTARG
           echo "NVMe mount point set as /mnt/$mnt_point";;
        l) # set LBA to 4KB
           override_4k_lba=$OPTARG
           echo "Override NVMe LBA 4KB support is set";;
        s) # set partition sector size
           sector_size=$OPTARG
           echo "NVMe partition alignment set as ${sector_size}s";;
        \?) # Invalid option
            echo "Error: Invalid option"
            Help
            exit;;
    esac
done

############################################################
# Main                                                     #
############################################################
# setup NVMe device for testing
echo 
echo "WARNING!!! SCRIPT THIS WILL ERASE THE NVMe. ALL DATA WILL BE LOST!!"
echo -e "Press Ctrl+C now to exit...\n"
sleep 10

# check if NVMe is mounted at /mnt/nvme
echo -e "Checking if "/mnt/${mnt_point}" is in use"
if [[ $(findmnt -M "/mnt/${mnt_point}") ]]; then
    echo -e "Mount point in use, unmounting...\n"
    umount "/mnt/${mnt_point}"
else
    echo -e "Mount point not in use\n"
fi

# get dev for nvme
if [[ -z "${nvme_dev}" ]]; then
    # if no NVMe dev option given then set automatically
    nvme_dev=`nvme list|awk '{print $1}'|grep dev`
    echo -e "Detected NVMe dev: $nvme_dev\n"
else
    # NVMe dev option specified
    nvme_dev="/dev/${nvme_dev}"
    echo -e "Using specified NVMe dev: $nvme_dev\n"
fi

# get nvme ctrl and ns
nvme_tmp=$nvme_dev
# set delimiter
IFS='/'
read -ra newarr <<< "$nvme_tmp"
nvme_ns=${newarr[2]}
echo -e "NVMe controller and namespace: $nvme_ns\n"

# check for 4kb lba size and format using 4kb if available
echo -e "Checking for supported LBA sizes\n"
if [[ $override_4k_lba == 0 ]];then
    # if no override then auto detect
    if [[ `nvme id-ns "$nvme_dev" -H |grep 'LBA Format'|grep 4096` ]];then
        echo -e "Found 4KB LBA support.. formatting NVMe\n"
        is_4k_lba=1
        nvme format -b 4096 "$nvme_dev" -fr
    else
        echo -e "Not found 4KB LBA support... formatting NVMe using default 512 bytes\n"
        nvme format -b 512 "$nvme_dev" -fr
    fi
else
    # override 4KB option is set
    echo -e "Override 4KB LBA support set... formatting NVMe using default 512 bytes\n"
    nvme format -b 512 "$nvme_dev" -fr
fi    

# mk partition table
echo -e "\nMake GPT partition table\n"
parted -a optimal "$nvme_dev" mklabel gpt

# mk partition
echo -e "Make aligned primary partition\n"
if [[ $is_4k_lba == 1 ]];then
    parted "$nvme_dev" mkpart primary ext4 256s 100%
else
    parted "$nvme_dev" mkpart primary ext4 ${sector_size}s 100%
fi

# check partition alignment
echo -e "Check parition 1 is aligned\n"
parted "$nvme_dev" align-check opt 1

# check partition table
echo -e "\nPartition table output: \n"
parted "$nvme_dev" print

# get partition dev number
nvme_part=`lsblk -l|grep -A1 "$nvme_ns"|grep part|awk '{print $1}'`
echo -e "Using first partition $nvme_part for file system\n"

# format with ext4
mkfs.ext4 /dev/$nvme_part

# set I/O scheduler as [none] for NVMe device
echo "Set NVMe device I/O scheduler to [none]" 
echo none > /sys/block/$nvme_ns/queue/scheduler

# check/create mount point
if [ -d "/mnt/${mnt_point}" ];then
    echo "Using "/mnt/${mnt_point}" mount point"
    echo ""
else
    echo "Creating "/mnt/${mnt_point}" mount point"
    echo ""
    mkdir "/mnt/${mnt_point}"
fi

# mount NVMe partition
echo -e "Mounting NVMe /dev/$nvme_part with noatime\n"
mount -o defaults,noatime /dev/$nvme_part "/mnt/${mnt_point}"

# End
echo "Finished NVMe setup"
echo
echo "Current configuration:"
echo "Device: $nvme_dev"
echo "Partition: /dev/$nvme_part"
echo "Alignment: ${sector_size}s"
echo "Mount: /mnt/$mnt_point"
echo "4KB LBA: $is_4k_lba"
