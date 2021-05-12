#!/usr/bin/env bash

set -e
#set -x
shopt -s expand_aliases

# use goto, ref: https://stackoverflow.com/questions/9639103/is-there-a-goto-statement-in-bash#answer-45538151
alias goto="cat >/dev/null <<"

#goto \#SETUP_INTERFACE

START_DIR=$(pwd)

INSTALL_DIR=$(cd basedir $1; pwd)

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

MMC=/dev/mmcblk0

#goto "#WRITE_IMAGE"
#goto "#MOUNT_IMAGE"
#goto "#SETUP_INTERFACE"

printf "Please insert your SD-Card into card reader.\n"

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
IMG_ZIP_CNT=$( set +e; ls -1 *raspbian*.zip 2>/dev/null | wc -l)
if [[ $IMG_ZIP_CNT -eq 1 ]]; then
  printf "Reusing existing archive.\n"
else  
  #curl -L -o raspbian_latest.zip https://downloads.raspberrypi.org/raspbian_latest 
  #curl -L -o raspbian_latest.zip https://downloads.raspberrypi.org/raspbian/images/raspbian-2019-04-09/2019-04-08-raspbian-stretch.zip
  #curl --location --remote-name --remote-header-name https://downloads.raspberrypi.org/raspbian/images/raspbian-2017-07-05/2017-07-05-raspbian-jessie.zip
  curl --location --remote-name --remote-header-name https://downloads.raspberrypi.org/raspbian/images/raspbian-2016-05-31/2016-05-27-raspbian-jessie.zip
fi
IMG_ZIP=$(ls -1 *raspbian*.zip)
printf "Using archive /tmp/$IMG_ZIP\n"
rm -f *raspbian*.img
unzip $IMG_ZIP

#WRITE_IMAGE

#goto "#MOUNT_IMAGE"

IMG=`ls -1 *raspbian*.img`
printf "Using image /tmp/$IMG\n"
pv $IMG | sudo dd of=$MMC bs=64M oflag=sync

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

# WLAN
if [[ -e $INSTALL_DIR/wpa_supplicant.conf ]]; then
  cp $INSTALL_DIR/wpa_supplicant.conf .
fi
# enable ssh
touch ssh

cat<<EOF >> config.txt
# for OTG mode
dtoverlay=dwc2
EOF

sed -i 's/rootwait /rootwait modules-load=dwc2,g_ether g_ether.dev_addr=AA:BB:CC:DD:EE:GG g_ether.host_addr=AA:BB:CC:DD:EE:FF /' cmdline.txt
#sed -i 's/rootwait /rootwait modules-load=dwc2,g_ether /' cmdline.txt

#cd /media/$USER/rootfs/etc/modprobe.d
#echo "options g_ether host_addr=AA:BB:CC:DD:EE:GG dev_addr=AA:BB:CC:DD:EE:FF" | sudo tee -a g_ether.conf

cd /media/$USER
sudo umount boot
sudo umount rootfs

sudo rmdir boot
sudo rmdir rootfs

#SETUP_INTERFACE

printf "Insert SDCARD into your Raspberry Pi and connect with USB cable to your PC.\n"

printf "Waiting for interface comming up.";
while [[ $(ip --oneline link show | grep "aa:bb:cc:dd:ee:ff" | wc -l) -eq 0 ]]; do
  sleep 1
  printf "."
done 
printf "\n"
IF_NAME=$(ip --oneline link show | grep aa:bb:cc:dd:ee:ff | awk '{split($0,a,": "); print a[2];}')
printf "Using interface $IF_NAME.\n";

if [[ $(nmcli connection | grep local_pi_shared | wc -l) -eq 0 ]]; then
  printf "Creating sharing connection to $IF_NAME\n"; 
  nmcli connection add type ethernet ifname $IF_NAME ipv4.method shared con-name local_pi_shared
fi

nmcli connection up local_pi_shared

printf "Finished. Now wait try ssh pi@raspberrypi.local, password \"raspberry\" \n";
