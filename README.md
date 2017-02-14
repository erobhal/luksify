NOTE!! This instruction is written for RHEL 6 with etx3/ext4 filesystems running on ProLiant Gen9 with internal USB storage!!

# Initiate the storage space for the LUKS keys

First make sure the server is a ProLiant G9 or newer and that “Embedded User Partition” is enabled. You can find the setting in the BIOS settings (F9 during boot) → System Configuration → BIOS/Platform COnfiguration → System Options → USB Options → Embedded User Partition.

If “Embedded User Partition” is not available on your model it's probably possible to use external USB storage. That has not been tested though. You must NOT store the keys on disk!!

Identify the storage. On a standard system with one disk it's probably published as /dev/sdb (and is around 1GB in size if using “Embedded User Partition”).

```$ fdisk -l

Disk /dev/sdb: 1073 MB, 1073741824 bytes
34 heads, 61 sectors/track, 1011 cylinders
Units = cylinders of 2074 * 512 = 1061888 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000```

Create a partition and create a filesystem on it.

```$ fdisk /dev/sdb

Command (m for help): p (make sure it hasn't already got a partition on it)

Command (m for help): n (create a new partition)

Command action
   e   extended
   p   primary partition (1-4)
p

Partition number (1-4): 1

First cylinder (1-1011, default 1): <enter>

Last cylinder, +cylinders or +size{K,M,G} (1-1011, default 1011): <enter>

Command (m for help): p

Disk /dev/sdb: 1073 MB, 1073741824 bytes
34 heads, 61 sectors/track, 1011 cylinders
Units = cylinders of 2074 * 512 = 1061888 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x3e44f269

   Device Boot      Start         End      Blocks   Id  System
/dev/sdb1               1        1011     1048376+  83  Linux

Command (m for help): w```

Now, create a filesystem on this partition.

```$ mkfs.ext3 /dev/sdb1```

# Install the latest version of luksify-tools

It will install the luksipc tool used to encrypt volumes in place. It will also install a dracut module that does an early mount of your key-store using /luks as mountpoint.

***IMPORTANT!*** Double check that your key-store has been detected correctly (usually /dev/sdb1) by reviewing /usr/share/dracut/modules.d/70luks-key/mount-keystore.sh after installation of luksify-tools. If not you'll have to tweak the scripts 'check' and 'mount-keystore.sh' located in /usr/share/dracut/modules.d/70luks-key/ and re-run:

```$ mkinitrd -f -v /boot/initramfs-$(uname -r).img $(uname -r)```

Before performing the actual encryption ***the key-store MUST be mounted on /luks*** (or the LUKS keys will end up on physical disk and that is NOT good!). To make sure the key-store is automatically mounted during boot, reboot the system before proceeding.

```$ reboot```

***After the reboot, make sure the key-store is mounted before proceeding! Please note that it won't be visible in /etc/mtab so it woun't show up if you type the mount command. You need to look in /proc/mounts.***

```$ grep '/luks' /proc/mounts```

***Make sure that the permissions on this directory and its content is correct. It should only be readable by root!***

# Encrypt a volume

I use the volume /dev/mapper/sysvg-lv_local (/local) in this example. The principle is the same for all volumes except the root partition.

***IMPORTANT!!!*** Make sure there is a functional backup of the volume in question. Theese steps are potentially harmful and may wipe your filesystem!!

First, we need to shrink the filesystem with at least 10MB to make room for the LUKS header. Check the current size and make a note of the new size. Also make sure there is enough free space to shrink it.

```$ tune2fs -l /dev/mapper/sysvg-lv_local

...
Inode count:              13107200
Block count:              52428800 <----
Reserved block count:     2620960
Free blocks:              51550210
Free inodes:              13105980
First block:              0
Block size:               4096     <----
...```

52428800 blocks x 4096 bytes = 204800 MB

204800MB - 10MB = 204790MB

Unmount the filesystem (for /var you probably need to boot into single user mode).

```$ umount /local```

If this fails there might be processes keeping it open. Check with the fuser command (fuser -m /local).

Make a filesystem check to make sure it's healthy.

```$ e2fsck -f /dev/mapper/sysvg-lv_local```

Rezise the filesystem using the new size.

```$ resize2fs /dev/mapper/sysvg-lv_local 204790M```

Make another check to make sure it's still healthy.

```$ e2fsck -f /dev/mapper/sysvg-lv_local```

Now it's time for the in-place encryption. Be careful and make sure you know what you're doing. You do not want to get this wrong.

***NOTE!! Make sure you don't overwrite an existing key!*** Choose a unique filename for the new key.

```$ cd /usr/local/sbin

$ ./luksipc -d /dev/mapper/sysvg-lv_local -k /luks/local_keyfile.bin```

Answer YES and let the tool do its job.

After the encryption stage is done without errors we can open the encrypted filesystem.

```$ cryptsetup luksOpen --key-file /luks/local_keyfile.bin /dev/mapper/sysvg-lv_local lv_local_decrypted```

Check the filesystem again.

```$ e2fsck -f /dev/mapper/lv_local_decrypted```

If everything looks ok you can mount it.

```$ mount /dev/mapper/lv_local_decrypted /local```

# The swap space

Since the swap space don't have a file system there is no need to schrink it before encryption. You can still use the luksipc tool but after it's done you need to re-initialize the new (encrypted) swap partition.

```$ mkswap /dev/mapper/lv_swap_decrypted```

Then add it to /etc/crypttab and /etc/fstab as before.

# Add a backup passphrase to LUKS and create a backup of the LUKS header.

Add a recovery key to be stored in a safe place.

```$ cryptsetup luksAddKey --key-file=/luks/local_keyfile.bin --key-slot 1 /dev/mapper/sysvg-lv_local```

When all keys has been added a backup of the LUKS header should be performed. This also needs to be stored at a safe place (more details to come).

```$ cryptsetup luksHeaderBackup /dev/mapper/sysvg-lv_local --header-backup-file=/luks/local_luks-header.bin```

NOTE: Yo don't need to backup LUKS header for the swap partition.

# Configure /etc/crypttab, /etc/fstab and prepare for reboot.

The filesystem needs to be added to /etc/crypttab

```lv_local_decrypted /dev/mapper/sysvg-lv_local /luks/local_keyfile.bin```

The mount entry in /etc/fstab needs to be changed to point to the opened device.

```Change: /dev/mapper/sysvg-lv_local /local ext4 defaults 1 2
To: /dev/mapper/lv_local_decrypted /local ext4 defaults 1 2```

Now you are ready to reboot. The key store should be mounted automatically and the encrypted filesystem should be available under /local.
