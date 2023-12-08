#
# flash-kernel: bootscr.odroid-rk3566
#

# Bootscript using the new unified bootcmd handling
#
# Expects to be called with the following environment variables set:
#
#  devtype              e.g. mmc/scsi etc
#  devnum               The device number of the given type
#  bootpart             The partition containing the boot files
#                       (introduced in u-boot mainline 2016.01)
#  prefix               Prefix within the boot partiion to the boot files
#  kernel_addr_r        Address to load the kernel to
#  fdt_addr_r           Address to load the FDT to
#  ramdisk_addr_r       Address to load the initrd to.
#
# The uboot must support the booti and generic filesystem load commands.

if test -z "${variant}"; then
    setenv variant m1
fi

setenv board odroid${variant}

load ${devtype} ${devnum}:${partition} ${loadaddr} ${prefix}bootparams.ini \
    &&  ini volumio ${loadaddr}

load ${devtype} ${devnum}:${partition} ${loadaddr} ${prefix}config.ini \
    &&  ini generic ${loadaddr}
if test -n "${overlay_profile}"; then
    ini overlay_${overlay_profile} ${loadaddr}
fi

if test -e ${devtype} ${devnum}:${partition} custom.ini; then
    load ${devtype} ${devnum}:${partition} ${loadaddr} ${prefix}custom.ini \
        && ini custom ${loadaddr}
    setenv overlays "${overlays} ${custom_overlays}"
    echo ${overlays} 
else
    echo "No 'custom.ini' used"
fi


setenv bootargs "net.ifnames=0 consoleblank=0 hwdevice=${hwdevice} loglevel=${verbosity} ${extraargs}"
setenv overlay_resize 8192

if test -n "${console}"; then
  setenv bootargs "${bootargs} console=${console}"
fi

if test -n "${default_console}"; then
  setenv bootargs "${bootargs} console=${default_console}"
fi

if test -z "${fdtfile}"; then
   setenv fdtfile "rk3566-odroid-${variant}.dtb"
fi

if test -z "${distro_bootpart}"; then
  setenv partition ${bootpart}
else
  setenv partition ${distro_bootpart}
fi

load ${devtype} ${devnum}:${partition} ${fdt_addr_r} ${prefix}rockchip/${fdtfile}
fdt addr ${fdt_addr_r}

if test "x{overlays}" != "x"; then
    for overlay in ${overlays}; do
        fdt resize ${overlay_resize}
        load ${devtype} ${devnum}:${partition} ${loadaddr} ${prefix}rockchip/overlays/${overlay}.dtbo \
                && fdt apply ${loadaddr}
    done
fi

load ${devtype} ${devnum}:${partition} ${kernel_addr_r} ${prefix}Image \
#unzip ${ramdisk_addr_r} ${kernel_addr_r}
load ${devtype} ${devnum}:${partition} ${ramdisk_addr_r} ${prefix}uInitrd 
echo "Booting Volumio from ${devtype} ${devnum}:${partition}..." 
booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}

echo "FATAL: script should not get here...."
# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr
