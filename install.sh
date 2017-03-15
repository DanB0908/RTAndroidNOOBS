#!/bin/bash

#
# Copyright (C) 2017 RTAndroid Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Android image installation script for Raspberry Pi 3
# Orignal Author: Igor Kalkov
# Modified By: Dan B.
# https://github.com/RTAndroid/android_vendor_brcm_rpi3_scripts/blob/aosp-7.1/scripts/install.sh
#

DEVICE_LOCATION=""
DEVICE_NAME=""
DEVICE_SIZE=""
DEVICE_SUFFIX=""

PARTITION=false
PARTITION_NEEDED=false
FORMAT=false

SIZE_P1=512   # exact size of the partition 1 (boot) in MB
SIZE_P2=2048  # exact size of the partition 2 (system) in MB
SIZE_P3=512   # exact size of the partition 3 (cache) in MB
SIZE_P4=1024  # minimum size of the partition 4 (userdata) in MB
SIZE_NOOBS=2060 # size required for NOOBS install (boot & system.img) in MB

# ------------------------------------------------
# Helping functions
# ------------------------------------------------

show_help()
{
cat << EOF
USAGE:
  $0 [-f] [-h] [-n] [-p] /dev/NAME
OPTIONS:
  -f  Format userdata and cache
  -h  Show help
  -n  Copy to drive in NOOBS format
  -p  (Re-)partition the sdcard
EOF
}

check_dependency()
{
    which $1 > /dev/null
    if (($? != 0)); then
        echo "ERR: $1 not found. Please install: \"$2\""
        exit 1
    fi
}

check_device()
{
    echo " * Checking access permissions..."

    if [ "$(sudo id -u)" != "0" ]; then
        echo "ERR: please make sure you are allowed to run 'sudo'!"
        exit 1
    fi

    echo " * Checking the device in $DEVICE_LOCATION..."

    if [[ -z "$DEVICE_LOCATION" ]]; then
        echo ""
        echo "ERR: device location not valid."
        exit 1
    fi

    if [[ ! -b "$DEVICE_LOCATION" ]]; then
        echo ""
        echo "ERR: no block device was found in $DEVICE_LOCATION!"
        exit 1
    fi

    echo " * Validating the device's size..."

    DEVICE_NAME=${DEVICE_LOCATION##*/}
    SIZE_FILE="/sys/block/$DEVICE_NAME/size"
    DEVICE_SIZE_SECTORS=$(cat $SIZE_FILE)

    if [[ ! -f "$SIZE_FILE" ]]; then
        echo ""
        echo "ERR: can't detect the size of the sdcard!"
    fi

    REQUIRED_SIZE_MB=$((SIZE_P1 + SIZE_P2 + SIZE_P3 + SIZE_P4))
    echo "  - minimum size: $REQUIRED_SIZE_MB MB"

    # DEVICE_SIZE [Sector] * 512 [Byte/Sector] / 1024 [Byte/KB] / 1024 [KB/MB] = SIZE [MB]
    DEVICE_SIZE_MB=$(($DEVICE_SIZE_SECTORS*512/1024/1024))
    echo "  - detected size: $DEVICE_SIZE_MB MB"

    if [[ $DEVICE_SIZE_MB -lt $REQUIRED_SIZE_MB ]]; then
        echo ""
        echo "ERR: please use an sdcard with more than $SIZE_SD MB."
        exit 1
    fi

    # some card readers mount the sdcard as /dev/mmcblkXp? instead of /dev/sdX?
    if [[ $DEVICE_NAME == "mmcblk"* ]]; then
        echo " * Using device suffix 'p' (mmcblk device)"
        DEVICE_SUFFIX="p"
    fi
}

check_partitions()
{
    echo " * Listing all available partitions..."
    PARTITION_LIST=$(sudo fdisk -l ${DEVICE_LOCATION} | grep "^/dev/")
    echo ""
    echo "$PARTITION_LIST"
    echo ""

    PARTITION_COUNT=$(wc -l <<< "${PARTITION_LIST}")
    echo " * Detected $PARTITION_COUNT partitions on $DEVICE_LOCATION"

    # allow all numbers if we are going to re-partition it anyways
    if [ "$PARTITION" = true ]; then
        echo "  - ignoring this count due to upcoming partitioning"
        if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS
            PARTITION_COUNT=1
        else
            PARTITION_COUNT=4
        fi
    fi

    if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS   
        if [ "${PARTITION_COUNT:-0}" -lt "1" ]; then
            echo "ERR: bad device in $DEVICE_LOCATION!"
            exit 1
        fi
    else        
        if [ "${PARTITION_COUNT:-0}" -ne "4" ]; then
            echo "ERR: bad device in $DEVICE_LOCATION!"
            exit 1
        fi
    fi
}

check_sizes()
{
    echo " * Validating partition sizes..."
    sleep 1

    PARTITION1_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}${DEVICE_SUFFIX}1/size")
    if [[ -z "$PARTITION1_SIZE_SECTORS" ]]; then
        echo "ERR: can't detect the size of the boot partition!"
        exit 1
    fi
    
    
    if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS
        PARTITION1_SIZE_MB=$(($PARTITION1_SIZE_SECTORS*512/1024/1024))

        if [[ $PARTITION1_SIZE_MB -lt $SIZE_NOOBS ]];
        then
            echo ""
            echo "ERR: the partition doesn't provide enough space!"
            exit 1
        fi
        
    else
        PARTITION1_SIZE_MB=$(($PARTITION1_SIZE_SECTORS*512/1024/1024))
        echo "  - boot) available: $PARTITION1_SIZE_MB MB, required: $SIZE_P1 MB"

        if [[ $PARTITION1_SIZE_MB -lt $SIZE_P1 ]];
        then
            echo ""
            echo "ERR: the 'boot' partition doesn't provide enough space!"
            exit 1
        fi

        PARTITION2_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}${DEVICE_SUFFIX}2/size")
        if [[ -z "$PARTITION2_SIZE_SECTORS" ]]; then
            echo "ERR: can't detect the size of the system partition!"
            exit 1
        fi

        PARTITION2_SIZE_MB=$(($PARTITION2_SIZE_SECTORS*512/1024/1024))
        echo "  - system) available: $PARTITION2_SIZE_MB MB, required: $SIZE_P2 MB"

        if [[ $PARTITION2_SIZE_MB -lt $SIZE_P2 ]];
        then
            echo ""
            echo "ERR: the 'system' partition doesn't provide enough space!"
            exit 1
        fi

        PARTITION3_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}${DEVICE_SUFFIX}3/size")
        if [[ -z "$PARTITION3_SIZE_SECTORS" ]]; then
            echo "ERR: can't detect the size of the cache partition!"
            exit 1
        fi

        PARTITION3_SIZE_MB=$(($PARTITION3_SIZE_SECTORS*512/1024/1024))
        echo "  - cache) available: $PARTITION3_SIZE_MB MB, required: $SIZE_P3 MB"

        if [[ $PARTITION3_SIZE_MB -lt $SIZE_P3 ]];
        then
            echo ""
            echo "ERR: the 'cache' partition doesn't provide enough space!"
            exit 1
        fi

        PARTITION4_SIZE_SECTORS=$(cat "/sys/block/${DEVICE_NAME}/${DEVICE_NAME}${DEVICE_SUFFIX}4/size")
        if [[ -z "$PARTITION4_SIZE_SECTORS" ]]; then
            echo "ERR: can't detect the size of the data partition!"
            exit 1
        fi

        PARTITION4_SIZE_MB=$(($PARTITION4_SIZE_SECTORS*512/1024/1024))
        echo "  - data) available: $PARTITION4_SIZE_MB MB, required: $SIZE_P4 MB"

        if [[ $PARTITION4_SIZE_MB -lt $SIZE_P4 ]];
        then
            echo ""
            echo "ERR: the 'data' partition doesn't provide enough space!"
            exit 1
        fi
    fi
}

wait_for_device()
{
    sleep 1
    sudo partprobe $DEVICE_LOCATION
}

create_partitions()
{
    local TEST=0

    # no partitioning was requested
    if [ "$PARTITION" = false ]; then
        echo " * Skipping partitioning..."
        return
    fi

    echo " * Destroying old partition table..."
    wait_for_device
    sudo dd if=/dev/zero of=$DEVICE_LOCATION bs=1024 count=1 conv=notrunc > /dev/null 2>&1
    ((TEST+=$?))

    echo " * Create a new partition table..."

    wait_for_device
    printf "o\nw\n" | sudo fdisk $DEVICE_LOCATION > /dev/null 2>&1
    ((TEST+=$?))

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: failed to recreate the partition table!"
        exit 1
    fi

    # re-read the partition table
    wait_for_device

    echo " * Start partitioning..."

    if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS
    
        # 1. partition -> NOOBS
        echo ""
        echo "  - creating 'boot'"
        printf "n\np\n1\n\n\nt\nb\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device
    else    
        # 1. partition -> boot
        echo ""
        echo "  - creating 'boot'"
        printf "n\np\n1\n\n+${SIZE_P1}M\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device


        # 2. partition -> system
        echo ""
        echo "  - creating 'system'"
        printf "n\np\n2\n\n+${SIZE_P2}M\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device

        # 3. partition -> cache
        echo ""
        echo "  - creating 'cache'"
        printf "n\np\n3\n\n+${SIZE_P3}M\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device

        # 4. partition -> userdata
        echo ""
        echo "  - creating 'userdata'"
        printf "n\np\n\n\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device

        # 5. set the partition type to "W95 FAT32 (LBA)"
        echo ""
        echo "  - setting correct partition type"
        printf "t\n1\nc\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device

        # 6. set the first partition as bootable
        echo ""
        echo "  - setting bootable flag"
        printf "a\n1\nw\n" | sudo fdisk $DEVICE_LOCATION
        wait_for_device
    fi

    echo ""
    echo " * Printing the new partition table..."

    printf "p\nq\n" | sudo fdisk $DEVICE_LOCATION
    echo ""
}

unmount_all()
{
    echo " * Unmounting mounted partitions..."
    sync

    if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS
        sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}1 > /dev/null 2>&1
    else
        sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}1 > /dev/null 2>&1
        sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}2 > /dev/null 2>&1
        sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}3 > /dev/null 2>&1
        sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}4 > /dev/null 2>&1
    fi
}

format_data()
{
    # no partitioning was requested
    if [ "$FORMAT" = false ]; then
        echo " * Skipping data format..."
        return
    fi

    echo " * Formatting data partitions..."
    local TEST=0

    echo "  - formatting 'cache'"
    echo ""
    sudo mkfs.ext4 -F -L cache ${DEVICE_LOCATION}${DEVICE_SUFFIX}3
    ((TEST+=$?))

    echo "  - formatting 'userdata'"
    echo ""
    sudo mkfs.ext4 -F -L userdata ${DEVICE_LOCATION}${DEVICE_SUFFIX}4
    ((TEST+=$?))

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error occured while formatting data partitions."
        exit 1
    fi
}

format_system()
{
    echo " * Formatting system partitions..."
    local TEST=0

    if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS    
    
        # no partitioning was requested
        if [ "$FORMAT" = false ]; then
            echo " * Skipping NOOBS format..."
            return
        fi
        
        echo " * Formatting NOOBS partition..."
        local TEST=0
        echo ""
        sudo mkfs.vfat -n boot -F 32 ${DEVICE_LOCATION}${DEVICE_SUFFIX}1
        ((TEST+=$?))
    else
        echo " * Formatting system partitions..."
        local TEST=0
    
        echo "  - formatting 'boot'"
        echo ""
        sudo mkfs.vfat -n boot -F 32 ${DEVICE_LOCATION}${DEVICE_SUFFIX}1
        ((TEST+=$?))

        echo ""
        echo "  - formatting 'system'"
        echo ""
        sudo mkfs.ext4 -F -L system ${DEVICE_LOCATION}${DEVICE_SUFFIX}2
        ((TEST+=$?))
    fi

    if [[ $TEST -gt 0 ]]; then
        echo "ERR: an error occured while formatting system partitions."
        exit 1
    fi
}

copy_files()
{
    echo " * Copying new system files..."
    DIR_NAME="/media/rpi-sd"

    BOOT_DIR="./boot"
    if [ ! -d $BOOT_DIR ]; then
        echo "ERR: boot directory not found!"
        exit 1
    fi

    SYSTEM_IMG="system.img"
    if [ ! -f $SYSTEM_IMG ]; then
        echo "ERR: system image not found!"
        exit 1
    fi

    NOOBS_DIR="./noobs"
    if [ ! -d $NOOBS_DIR ]; then
        echo "ERR: noobs directory not found!"
        exit 1
    fi

    echo "   - mounting the boot partition to $DIR_NAME"
    sudo rm -rf $DIR_NAME > /dev/null 2>&1
    sudo mkdir -p $DIR_NAME
    sudo mount -t vfat -o rw ${DEVICE_LOCATION}${DEVICE_SUFFIX}1 $DIR_NAME

    
    if [ "$NOOBS_INSTALL" = true ]; then # Modified for NOOBS
    
        echo "   - creating NOOBS install tar"
        sudo mkdir -p $DIR_NAME/os/Android
        sudo tar -cvpf $DIR_NAME/os/Android/boot.tar ./$BOOT_DIR/*
        echo "   - copying the NOOBS files"
        sudo cp -fr $NOOBS_DIR/* $DIR_NAME/os/Android/ 
        echo "   - copying the system.img"
        sudo cp -r $SYSTEM_IMG $DIR_NAME/os/Android/ 

        echo "   - unmounting the NOOBS partition"
        sync
        sudo umount -l $DIR_NAME
        sudo rm -rf $DIR_NAME
    else
           
        echo "   - copying boot files" 
        sudo cp -fr $BOOT_DIR/* $DIR_NAME/

        echo "   - unmounting the boot partition"
        sync
        sudo umount -l $DIR_NAME
        sudo rm -rf $DIR_NAME

        echo "   - writing the system image"
        sudo dd if=$SYSTEM_IMG of=${DEVICE_LOCATION}${DEVICE_SUFFIX}2 bs=1M oflag=direct
    fi
}


# --------------------------------------
# Script entry point
# --------------------------------------


# save the passed options
while getopts ":fhnp" flag; do
case $flag in
    "h") SHOW_HELP=true ;;
    "n") NOOBS_INSTALL=true;;
    "p") PARTITION=true ;;
    "f") FORMAT=true ;;
    *)
         echo ""
         echo "ERR: invalid option (-$flag $OPTARG)"
         echo ""
         show_help
         exit 1
esac
done

# don't do anything else
if [[ "$SHOW_HELP" = true ]]; then
    show_help
    exit 1
fi

# what left after the parameters has to be the device
shift $(($OPTIND - 1))
DEVICE_LOCATION="$1"

# no target provided
if [[ -z "$DEVICE_LOCATION" ]]; then
    echo ""
    echo "ERR: missing the path to the sdcard!"
    echo ""
    show_help
    exit 1
fi

echo "Installation script for RPi started."
echo "Target device: $DEVICE_LOCATION"
echo "Perform partitioning: $PARTITION"
echo "Perform formatting: $FORMAT"
echo ""

check_dependency partprobe parted
check_device
unmount_all
check_partitions
create_partitions
check_sizes
unmount_all
format_data
format_system
copy_files

echo ""
echo "Installation successful. You can now put your sdcard in the RPi."
