The Crystal Bootloader
================================================================================

A small x86 bootloader that fits in the first 16 sectors of the disk (8 Kb).
Crystal expects the disk to have the following layout (note that "Offset" and
"Size" are in units of 512-bytes sectors):

| Section         | Offset  | Size  | Description  |
| --------------- | ------- | ----- | ------------ |
| Bootsector      | 0          | 1  | The 1st stage of crystal and the MBR partition table. |
| Crystal stage 2 | 1          | 15 | The 2nd stage of crystal. |
| Kernel Command Line | 16     | 1  | The command line to pass to the kernel. |
| Kernel          | 17         | K  | The Kernel image |
| Initramfs Info  | 17 + K + 1 | 1  | Information about the initramfs |
| Initramfs       | 17 + K + 2 | R  | The initramfs image |

## Initramfs Info Sector

| Name  | Offset | Size | Description |
| ----- | ------ | ---- | ----------- |
| Size  | 0      | 4    | Size of the initramfs in bytes |


## How to build
```
nasm -o crystal.bin crystal.asm -l crystal.list
```

## How to install

You can use the provided script (witten in python) to install/setup a disk image with crystal.

#### Install crystal to the first 16 sectors of the disk:

```
./crystal-img install-crystal <disk-image> crystal.bin
```

> Note: this will leave the MBR partition table intact

#### Read/Modify the kernel command line:

```
./crystal-img read-kernel-cmd-line <disk-image>
./crystal-img set-kernel-cmd-line <disk-image> <args>...
```

#### Install the kernel and/or an initramfs

```
./crystal-img install-kernel <disk-image> <kernel-reserve-size> <kernel-image> [<initramfs>]
```

Example:

```
./crystal-img install-kernel disk.img 15M zImage initramfs.cpio.gz
```

# A Note On Bootloaders

Crystal chooses to use the simplest interface to load the kernel/initramfs, raw disk sector reads. It purposely does not include filesystem drivers that would allow Crystal to load these images from a filesystem. This allows Crystal to be much smaller than other bootloaders and doesn't need to duplicate filesystem drivers that already exist in the kernel. This also means that the kernel/initramfs must be installed directly on the disk instead of in a filesystem. The disadvantage of this is that you'll need to reserve space on the disk for these images.  This also means that if the sizes change significantly you may need to reserve more space which would require an awkward operation of moving partitions around to accomodate this.

Crystal doesn't have an interactive shell like other bootloaders. These shells are great for "isolated" systems that need to be able recover without the help of other machines. For machines whose disk can be modified outside of themselves, these shells aren't necessary because the disk can be recovered by another host. Examples of these kinds of machines would be qemu simulators or devices with removable/flashable disks. Crystal leverages the tools on the host to recover and configure the bootloader instead of embedding those tools inside itself. This makes Crystal sufficient for static systems that don't change or ones that have another mechanism to modify the disk outside the machine that is being booted by Crystal.

# TODO:

* Generate the bootloader assembly code based on configuration (i.e. change verbosity level)
