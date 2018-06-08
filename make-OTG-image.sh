#!/usr/bin/env bash

set -e
#set -x
shopt -s expand_aliases

# use goto, ref: https://stackoverflow.com/questions/9639103/is-there-a-goto-statement-in-bash#answer-45538151
alias goto="cat >/dev/null <<"

START_DIR=$(pwd)

cleanup() {
  if [[ $? -ne 0 && $? -ne 130 ]]; then
  cat <<EOF

  ______ _____  _____   ____  _____  
 |  ____|  __ \|  __ \ / __ \|  __ \ 
 | |__  | |__) | |__) | |  | | |__) |
 |  __| |  _  /|  _  /| |  | |  _  / 
 | |____| | \ \| | \ \| |__| | | \ \ 
 |______|_|  \_\_|  \_\\____/|_|  \_\

EOF
  fi
  cd $START_DIR
}

trap cleanup EXIT

#goto "#WRITE_IMAGE"

printf "Please insert your SD-Card into card reader.\n"

MMC=/dev/mmcblk0
printf "waiting for $MMC.\n";
while [[ ! -e $MMC ]]; do
  sleep 1;
  printf "."
done
printf "\n"
printf "Going to overide $MMC, all data will be lost. Please type enter to proceed, or Ctrl-c to abort.";
read

cd /tmp

# try reuse existing image
IMG_ZIP_CNT=`ls -1 *raspbian-stretch.zip | wc -l`
if [[ $IMG_ZIP_CNT -gt 1 ]]; then
  printf "To many images found in /tmp, remove some or all:\n\n";
  ls -1 *raspbian-stretch.zip
elif [[ $IMG_ZIP_CNT -eq 1 ]]; then
  printf "Reusing existing archive.\n"
else  
  curl -JLO https://downloads.raspberrypi.org/raspbian_latest 
fi
IMG_ZIP=`ls -1 *raspbian-stretch.zip`
printf "Using archive /tmp/$IMG_ZIP\n"
rm -f *raspbian-stretch.img
unzip $IMG_ZIP

#WRITE_IMAGE

#goto "#MOUNT_IMAGE"

IMG=`ls -1 *raspbian-stretch.img`
printf "Using image /tmp/$IMG\n"
sudo dd if=$IMG of=$MMC bs=64M status=progress oflag=sync
sync

#MOUNT_IMAGE

#goto "#MODIFY_IMAGE"

printf "Please eject SDCARD.\n"
while [[ -e $MMC ]]; do
  sleep 1;
  printf "."
done
printf "\n"
printf "Please insert SDCARD again.\n"
while [[ ! -e $MMC ]]; do
  sleep 1;
  printf "."
done
printf "\n"

cd /media/$USER
if [[ ! -e boot ]]; then
  sudo mkdir boot
fi
if [[ ! -e rootfs ]]; then
  sudo mkdir rootfs
fi

printf "Mounting SDCARD filesystems.\n"
MNT_OPTS_BOOT="-o rw,nosuid,nodev,relatime,uid=`id -u`,gid=`id -g`,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,showexec,utf8,flush,errors=remount-ro,uhelper=udisks2"
MNT_OPTS_ROOTFS="-o rw,nosuid,nodev,relatime,data=ordered,uhelper=udisks2"
if [[ `mount | grep ${MMC}p1 | wc -l` -eq 0 ]]; then
	sudo mount -t vfat $MNT_OPTS_BOOT ${MMC}p1 boot
fi

if [[ `mount | grep ${MMC}p2 | wc -l` -eq 0 ]]; then
	sudo mount -t ext4 $MNT_OPTS_ROOTFS ${MMC}p2 rootfs
fi

#MODIFY_IMAGE

#goto "#SETUP_INTERFACE"

cd /media/$USER/boot

if [[ ! -e config.txt.org ]]; then
	cp config.txt config.txt.org
fi

cat<<EOF >> config.txt
# for OTG mode
dtoverlay=dwc2
EOF

if [[ ! -e cmdline.txt.org ]]; then
	cp cmdline.txt cmdline.txt.org
fi

sed -i 's/rootwait /rootwait modules-load=dwc2,g_ether g_ether.dev_addr=AA:BB:CC:DD:EE:GG g_ether.host_addr=AA:BB:CC:DD:EE:FF /' cmdline.txt

# enable ssh
touch ssh

cd /media/$USER/rootfs/etc/modprobe.d
echo "options g_ether host_addr=AA:BB:CC:DD:EE:GG dev_addr=AA:BB:CC:DD:EE:FF" | sudo tee -a g_ether.conf

cd /media/$USER

sudo umount boot
sudo umount rootfs

sudo rmdir boot
sudo rmdir rootfs

#SETUP_INTERFACE

printf "Insert SDCARD into your Raspberry Pi and connect with USB cable to your PC.\n"
printf "Waiting for interface comming up.";
while [[ `/sbin/ifconfig | grep "aa:bb:cc:dd:ee:ff" | wc -l` -eq 0 ]]; do
  sleep 1
  printf "."
done 
printf "\n"
IF_NAME=`/sbin/ifconfig | grep "aa:bb:cc:dd:ee:ff" | cut -d' ' -f1`
printf "Hardware interface is named $IF_NAME, trying to rename it in connection manager as \"PI\".\n";

while [[ `nmcli --terse --fields NAME,DEVICE con show | grep $IF_NAME | wc -l` -eq 0 ]]; do
  sleep 1
  printf "."
done;
printf "\n"
CON_NAME=`nmcli --terse --fields NAME,DEVICE con show | grep $IF_NAME | cut -d: -f1`
printf "Renaming \"$CON_NAME\" to \"PI\"\n";
nmcli con modify "$CON_NAME" connection.id PI
printf "Modifying connection PI to \"shared to other computers\"\n"; 
nmcli con mod PI ipv4.method shared
printf "Finished. Now wait 60s and try ssh pi@raspberrypi.local, password \"raspberry\" \n";

