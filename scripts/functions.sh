#!/bin/bash

get_toolchains() {
  if [ ! -d "/opt/toolchains" ]; then
    log "Using sudo to create the toolchains folder" "info"
    sudo mkdir -p "/opt/toolchains"
  fi  

  log "Checking gcc"
  if [ ! -d "/opt/toolchains/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu" ]; then

    log " Downloading u-boot and kernel gcc toolchain"
    wget http://releases.linaro.org/components/toolchain/binaries/7.4-2019.02/aarch64-linux-gnu/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
    log "Unpacking the toolchain"
    sudo tar xvf gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz -C /opt/toolchains/ 1> /dev/null 2>&1
    rm gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz
    log "u-boot & kernel gcc toolchain downloaded succesfully" "okay"
  fi

  log "Checking xpack-riscv-none-embed-gcc"
  if [ ! -d "/opt/toolchains/xpack-riscv-none-embed-gcc-10.2.0-1.2" ]; then
  
    log "Downloading xpack-riscv-none-embed-gcc toolchain"
    wget http://github.com/xpack-dev-tools/riscv-none-embed-gcc-xpack/releases/download/v10.2.0-1.2/xpack-riscv-none-embed-gcc-10.2.0-1.2-linux-x64.tar.gz
    log "Unpacking the toolchain"
    sudo tar xvf xpack-riscv-none-embed-gcc-10.2.0-1.2-linux-x64.tar.gz -C /opt/toolchains/ 1> /dev/null 2>&1
    rm xpack-riscv-none-embed-gcc-10.2.0-1.2-linux-x64.tar.gz
    log "xpack-riscv-none-embed-gcc toolchain downloaded succesfully" "okay"
  fi
  log "Get toolchains finished" "okay"
}

get_uboot_sources() {
  if [ ! -d "./u-boot" ]; then
    log "Cloning u-boot repository"
    git clone ${UBOOTSOURCE} -b ${UBOOTBRANCH}
    pushd u-boot 1> /dev/null 2>&1
      git submodule init
      git submodule update
    popd 1> /dev/null 2>&1
  fi
  log "U-boot sources present" "okay"
}

compile_uboot() {

  pushd u-boot 1> /dev/null 2>&1
    log "Compiling u-boot"
    ./make.sh odroid_rk3566 
    log "Compiling u-boot finished, copying uboot.img"
  popd 1> /dev/null 2>&1
  log "U-boot complilation completed successfully" "okay"
}

get_kernel_sources() {
  log "Checking kernel sources"
  if [ ! -d "${KERNELTARGET}" ]; then  
    log "Cloning the kernel repo" "info"
    git clone --depth 1 ${KERNELSOURCE} -b ${KERNELBRANCH} ${KERNELTARGET}
  else
    pushd ${KERNELTARGET} 1> /dev/null 2>&1
      log "Already present. Cleaning and pull..."
      git clean -qdfx
      git reset --hard HEAD~0 1> /dev/null 2>&1
      git pull
    popd 1> /dev/null 2>&1
  fi
  log "Kernel sources present and up-to-date" "okay"
  
  log "Adding the default kernel configuration" "info"
  if [ -f ${C}/board/${KERNELCONFIG} ]; then
    cp ${C}/board/${KERNELCONFIG} ${KERNELTARGET}/arch/arm64/configs/${KERNELCONFIG}
  else
    log "Default kernel configuration not used" "info"
  fi  
  
}

apply_existing_patches() {
  log "Checking custom patches"
  pushd ${KERNELTARGET} 1> /dev/null 2>&1
  if [ ! -d ${PATCHDIR}/${KERNELTARGET} ] ; then
    log "No custom patches found" "wrn"  
  else
    log "Applying accumulative kernel patches"
    for f in ${PATCHDIR}/${KERNELTARGET}/*.patch
      do
      log "Appying $f"
      git apply $f 
    done
  fi
  log "Existing patches applied successfully" "okay"
}

add_custom_sources() {
  log "Checking custom kernel sources"
  if [ ! -d ${C}/sources/${KERNELTARGET} ] ; then
    log "No custom kernel sources found" "info"
  else
    cp -dR ${C}/sources/${KERNELTARGET}/* .
    log "Additional kernel sources added" "okay" 
  fi
}

create_custom_patches() {
  if [ "${KERNELPATCHES}" == "yes" ]; then
    for f in ${PATCHDIR}/${KERNELTARGET}/*.patch
      do
      log "Backup $f"
      cp ${f} ${f}_$(date +%Y.%m.%d-%H.%M) 1> /dev/null 2>&1
    done
    log "Now ready for additional sources and patches" "Info"
    read -p "Press [Enter] key to resume ..."
    git add * 1> /dev/null 2>&1
    git commit -m "accumulated-custom-volumio" 1> /dev/null 2>&1
    [ ! -d "${PATCHDIR}/${KERNELTARGET}" ] && mkdir -p ${PATCHDIR}/${KERNELTARGET}
    git format-patch -1 HEAD -o ${PATCHDIR}/${KERNELTARGET} 1> /dev/null 2>&1
  fi
  log "Custom patches applied and saved" "okay"
}

configure_kernel() {

  log "Preparing volumio kernel config file"
  make clean
 
  log "Using configuration 'arch/x86/configs/${KERNELCONFIG}'" "info"
  make ${KERNELCONFIG}

  if [ "${CONFIGURE_KERNEL}" == "yes" ]; then
    make menuconfig
    log "Copying .config to volumio kernel config"
    cp .config arch/arm64/configs/${KERNELCONFIG}
    log "Kernel configuration successfully completed" "okay"
  else
    log "Kernel configure skipped by configuration" "info"
  fi
  
}

compile_kernel() {
  
  log "Compiling dts, image and modules"
  make -j$(expr $(expr $(nproc) \* 6) \/ 5)
  log "Kernel compilation successfully completed" "okay"  
}

populate_platform_m1s() {

  if [ ! -d ${C}/${KERNELTARGET} ]; then
    log "Nothing to process" "err"
    exit 255
  fi
  
  log "Creating platform '${C}/${T}' files"
  [[ -d "${C}/${T}" ]] && rm -rf "${C}/${T}"
  mkdir -p "${C}/${T}"/boot/rockchip/overlays
  mkdir -p "${C}/${T}"/boot/u-boot
  mkdir -p "${C}/${T}"/lib/firmware
  mkdir -p "${C}/${T}"/lib/systemd/system/
  mkdir -p "${C}/${T}"/u-boot

  log "Saving kernel"
  cd ${C}/${KERNELTARGET} 
  cp arch/arm64/configs/${KERNELCONFIG} "${C}"/board/${KERNELCONFIG}_latest
  cp arch/arm64/boot/Image "${C}/${T}"/boot
  kver=`make kernelrelease`-`date +%Y.%m.%d-%H.%M`
  cp arch/arm64/configs/${KERNELCONFIG}  "${C}/${T}"/boot/config-${kver}
  log "Kernel image & configuration saved" "okay"
  
  log "Modules_install" 
  make modules_install ARCH=arm64 INSTALL_MOD_PATH="${C}/${T}"
  log "Modules installed and saved" "okay"
  
  log "Adding firmware"
  cp -r ${C}/firmware "${C}/${T}"/lib
  log "Firmware added " "okay"
  
  log "Saving dtb & overlays"
  cp arch/arm64/boot/dts/rockchip/${D} "${C}/${T}"/boot/rockchip
  cp -r arch/arm64/boot/dts/rockchip/overlays/${T}/*.dtbo "${C}/${T}"/boot/rockchip/overlays
  log "DTB's and overlays saved" "okay"
  
  log "Saving u-boot & spl"
  cp ${C}/u-boot/uboot.img ${C}/${T}/u-boot
  cp ${C}/u-boot/idblock.bin ${C}/${T}/u-boot
  # for the installer: need it to /boot as well
  cp ${C}/${T}/u-boot/* ${C}/${T}/boot/u-boot
  log "U-boot & spl saved" "okay"
  
  log "Copying bootparams"
  cp ${C}/bootscripts/${T}.boot.cmd "${C}/${T}"/boot/boot.cmd
  cp ${C}/bootparams/${T}.bootparams.ini "${C}/${T}"/boot/bootparams.ini
  cp ${C}/bootparams/${T}.config.ini "${C}/${T}"/boot/config.ini
  cp ${C}/bootparams/${T}.custom.ini.tmpl "${C}/${T}"/boot/custom.ini.tmpl 
  
  mkimage -C none -A arm -T script -d "${C}/${T}"/boot/boot.cmd "${C}/${T}"/boot/boot.scr
  log "bootparameters prepared and saved " "okay"
  
  log "Compressing "${C}/${T}""
  cd ${C}
  tar cvfJ ${T}.tar.xz ./${T} 1> /dev/null 2>&1
  rm -rf ${T}
}

populate_platform_rz3() {

  if [ ! -d ${C}/${KERNELTARGET} ]; then
    log "Nothing to process" "err"
    exit 255
  fi
  
  log "Creating platform '${C}/${T}' files"
  [[ -d "${C}/${T}" ]] && rm -rf "${C}/${T}"
  mkdir -p "${C}/${T}"/boot/dtb/rockchip/overlays
  mkdir -p "${C}/${T}"/boot/u-boot
  mkdir -p "${C}/${T}"/lib/firmware
  mkdir -p "${C}/${T}"/lib/systemd/system/
  mkdir -p "${C}/${T}"/u-boot

  log "Saving kernel"
  cd ${C}/${KERNELTARGET} 
  cp arch/arm64/configs/${KERNELCONFIG} "${C}"/board/${KERNELCONFIG}_latest
  cp arch/arm64/boot/Image "${C}/${T}"/boot
  kver=`make kernelrelease`-`date +%Y.%m.%d-%H.%M`
  cp arch/arm64/configs/${KERNELCONFIG}  "${C}/${T}"/boot/config-${kver}
  log "Kernel image & configuration saved" "okay"
  
  log "Modules_install" 
  make modules_install ARCH=arm64 INSTALL_MOD_PATH="${C}/${T}"
  log "Modules installed and saved" "okay"
  
  log "Adding firmware"
  cp -r ${C}/firmware "${C}/${T}"/lib
  log "Firmware added " "okay"
  
  log "Saving dtb & overlays"
  cp arch/arm64/boot/dts/rockchip/${D} "${C}/${T}"/boot/dtb/rockchip
  cp -r arch/arm64/boot/dts/rockchip/overlays/${T}/*.dtbo "${C}/${T}"/boot/dtb/rockchip/overlays
  log "DTB's and overlays saved" "okay"
  
  log "Saving u-boot & spl"
  dpkg-deb -x "${C}/${UBOOTSOURCE}" "${C}/${T}"
  cp ${C}/${T}/usr/lib/u-boot/radxa-zero3/u-boot.itb ${C}/${T}/u-boot
  cp ${C}/${T}/usr/lib/u-boot/radxa-zero3/idbloader.img ${C}/${T}/u-boot
  # for the installer: need it to /boot as well
  cp ${C}/${T}/u-boot/* ${C}/${T}/boot/u-boot
  rm -rf "${C}/${T}"/usr
  log "U-boot & spl saved" "okay"
  
  
  
  log "Copying bootparams"
  cp ${C}/bootscripts/${T}.boot.cmd "${C}/${T}"/boot/boot.cmd
  cp ${C}/bootparams/${T}.armbianEnv.txt "${C}/${T}"/boot/armbianEnv.txt
  
  mkimage -C none -A arm -T script -d "${C}/${T}"/boot/boot.cmd "${C}/${T}"/boot/boot.scr
  log "bootparameters prepared and saved " "okay"
  
  log "Compressing "${C}/${T}""
  cd ${C}
  tar cvfJ ${T}.tar.xz ./${T} 1> /dev/null 2>&1
  rm -rf ${T}
}


