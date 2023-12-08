#!/bin/bash

C=${PWD}
source ${C}/board/boardconfig.m1s
source ${C}/scripts/helpers.sh
source ${C}/scripts/functions.sh

log "Using these parameters" "cfg"
log "Board                 : ${T}" "cfg"
log "DTB                   : ${D}" "cfg"
log "Compile u-boot        : $COMPILE_UBOOT" "cfg"
log "Using u-boot          : $U" "cfg"
log "Using kernel branch   : $B" "cfg"
log "Add custom patches    : $KERNELPATCHES" "cfg"
log "Compile kernel        : $COMPILE_KERNEL" "cfg"
log "Using kernel config   : $KERNELCONFIG" "cfg"
log "Configure kernel      : $CONFIGURE_KERNEL" "cfg"
log "Using patch directory : $PATCHDIR" "cfg"

get_toolchains

if [ "${COMPILE_UBOOT}" == "yes" ]; then
  log "Checking sources" "info"
  get_uboot_sources
  
  log "Comiling u-boot" "info"
  compile_uboot
else
  log "Compiling u-boot skipped by configuration" "info"
fi

if [ "${COMPILE_KERNEL}" == "yes" ]; then

  get_kernel_sources
  
  apply_existing_patches
  
  add_custom_sources
  
  create_custom_patches
  
  configure_kernel
  
  compile_kernel

else
  log "Compiling kernel skipped by configuration" "info" 
fi

populate_platform_m1s

log "Platform creation finished successfully" "okay"
