#!/bin/sh

set -ex

if [ -z "$part1" ] || [ -z "$part2" ] || [ -z "$part3" ] || [ -z "$part4" ]; then
  printf "Error: missing environment variable part1 or part2\n" 1>&2
  exit 1
fi

mkdir -p /tmp/1 /tmp/2 /tmp/2/ramdisk

mount "$part1" /tmp/1

path_loc=`find / -type d | grep Android`

tar xf $path_loc/boot.tar -C /tmp/1

mv /tmp/1/boot/* /tmp/1

rm -rf /tmp/1/boot*

dd if=$path_loc/system.img of=${part2} bs=1M

mv /tmp/1/ramdisk.img /tmp/2/ramdisk.cpio.gz 

cd /tmp/2

gzip -d ramdisk.cpio.gz

cd /tmp/2/ramdisk

$path_loc/cpio -i -F ../ramdisk.cpio
p2=`echo ${part2} | sed -e 's/dev/dev\/block/g'`
p3=`echo ${part3} | sed -e 's/dev/dev\/block/g'`
p4=`echo ${part4} | sed -e 's/dev/dev\/block/g'`

sed /tmp/2/ramdisk/fstab.rpi3 -i -e "s|^.* /system |$p2  /system |"
sed /tmp/2/ramdisk/fstab.rpi3 -i -e "s|^.* /cache |$p3  /cache |"
sed /tmp/2/ramdisk/fstab.rpi3 -i -e "s|^.* /data |$p4  /data |"

$path_loc/cpio -i -t -F ../ramdisk.cpio | $path_loc/cpio -o -H newc > ../ramdisk_new.cpio

mv ../ramdisk_new.cpio /tmp/1/ramdisk.img

cd /

umount /tmp/1
