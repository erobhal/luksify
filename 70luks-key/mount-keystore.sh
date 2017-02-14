#!/bin/sh

# Load the kernel modules necessary
modprobe usb-storage

# Wait a maximum of 5 seconds until DEV
# is available before proceeding
i=0
while ! [ -b DEV ]
  do
    sleep 1
    i=$(($i+1))
    if [ $i -gt 4 ]
      then
        break
      fi
  done

# Try to mount /luks
mount -v -t FS DEV $NEWROOT/luks

