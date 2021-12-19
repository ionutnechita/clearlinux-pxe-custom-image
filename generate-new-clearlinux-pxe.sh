#!/bin/bash

##Copyright (c) 2021, ClearLinux PXE custom image, Ionut Nechita.
##All rights reserved.
##SPDX-License-Identifier: Apache-2.0

dockerImage="clearlinux/clr-sdk:latest"
activeContainer=$(docker ps | grep $dockerImage | awk '{ print $1}')

echo -e "\n- [INFO $(date)] - Pull $dockerImage"
docker pull $dockerImage

echo -e "\n- [INFO $(date)] - Stop and remove old containers $dockerImage"
if [[ $activeContainer != '' ]]; then echo Stop && docker stop $activeContainer && echo Remove && docker rm $activeContainer; fi

echo -e "\n- [INFO $(date)] - Create new container $dockerImage"
docker run -d -i -v /dev/shm:/dev/shm $dockerImage

nextContainer=$(docker ps | grep $dockerImage | awk '{ print $1}')
echo -e "\n- [INFO $(date)] - Run simple ls command in container $dockerImage - $nextContainer"
docker exec -i $nextContainer bash -c "ls"

echo -e "\n- [INFO $(date)] - Clone latest kernel using git command"
docker exec -i $nextContainer bash -c "cd /dev/shm && \
    git clone https://github.com/torvalds/linux.git -b master vanilla-linux"

echo -e "\n- [INFO $(date)] - View /usr/lib/os-release for $nextContainer"
docker exec -i $nextContainer bash -c "cat /usr/lib/os-release"

echo -e "\n- [INFO $(date)] - Download original config kernel from clearlinux-pkgs/linux in container $dockerImage - $nextContainer"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    rm -f config config.* .config config-changed && \
    wget https://raw.githubusercontent.com/clearlinux-pkgs/linux/master/config && \
    mv config .config"

echo -e "\n- [INFO $(date)] - Change original config kernel with extra option"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    sed -i 's/# CONFIG_EXT2_FS is not set/CONFIG_EXT2_FS=y/' .config && \
    sed -i 's/# CONFIG_EXT3_FS is not set/CONFIG_EXT3_FS=y/' .config && \
    sed -i 's/# CONFIG_STMMAC_SELFTESTS is not set/CONFIG_STMMAC_SELFTESTS=y/' .config && \
    sed -i 's/CONFIG_STMMAC_ETH=m/CONFIG_STMMAC_ETH=y/' .config && \
    sed -i 's/CONFIG_STMMAC_PLATFORM=m/CONFIG_STMMAC_PLATFORM=y/' .config && \
    sed -i 's/CONFIG_STMMAC_PCI=m/CONFIG_STMMAC_PCI=y/' .config && \
    sed -i 's/CONFIG_MMC_SDHCI_PLTFM=m/CONFIG_MMC_SDHCI_PLTFM=y/' .config && \
    sed -i 's/CONFIG_MMC_BLOCK_MINORS=8/CONFIG_MMC_BLOCK_MINORS=16/' .config && \
    sed -i 's/CONFIG_BLK_DEV_RAM=m/CONFIG_BLK_DEV_RAM=y/' .config && \
    sed -i 's/CONFIG_BLK_DEV_RAM_COUNT=16/CONFIG_BLK_DEV_RAM_COUNT=1/' .config && \
    sed -i 's/CONFIG_BLK_DEV_RAM_SIZE=16384/CONFIG_BLK_DEV_RAM_SIZE=65536/' .config && \
    cat .config | grep -E 'CONFIG_EXT2_FS|CONFIG_EXT3_FS|CONFIG_STMMAC_SELFTESTS|CONFIG_STMMAC_ETH|CONFIG_STMMAC_PLATFORM|CONFIG_STMMAC_PCI|CONFIG_MMC_SDHCI_PLTFM|CONFIG_MMC_BLOCK_MINORS|CONFIG_BLK_DEV_RAM' | tee -a config-changed"

echo -e "\n- [INFO $(date)] - Run make oldconfig"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    set +e && yes '' | make oldconfig && \
    cat .config | head -10"

echo -e "\n- [INFO $(date)] - Run make"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    set +e && make clean -j && \
    make -j `getconf _NPROCESSORS_ONLN` ARCH=x86_64 LOCALVERSION=-edgefoundation CC_VERSION_TEXT='Special OS for Build Edge Kernel'"

echo -e "\n- [INFO $(date)] - Run make modules"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    set +e && rm -rf modules && \
    mkdir -p modules && \
    make INSTALL_MOD_PATH=modules modules_install -j `getconf _NPROCESSORS_ONLN` && \
    cd modules/lib/modules && \
    tar czf ../modules.tar.gz . && \
    cd ../../../ && \
    pwd"

echo -e "\n- [INFO $(date)] - View version kernel"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    rm -f version-kernel && \
    cat .config| grep '# Linux' | cut -d' ' -f3 | tee -a version-kernel && \
    ls version-kernel"

echo -e "\n- [INFO $(date)] - Download clear linux pxe archive"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    rm -rf initramfs && \
    mkdir initramfs && \
    cd initramfs && \
    wget https://cdn.download.clearlinux.org/image/clear-$(wget  -qO - https://cdn.download.clearlinux.org/latest)-pxe.tar.xz && \
    cd ../ && \
    echo $(wget  -qO - https://cdn.download.clearlinux.org/latest) > clearlinux-version && \
    ls clearlinux-version"

echo -e "\n- [INFO $(date)] - Extract clear linux pxe and initrd archive"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cd initramfs && \
    tar xf clear-*-pxe.tar.xz && \
    mkdir extracted-initrd && \
    cd extracted-initrd && \
    mv ../initrd . && \
    zcat initrd | cpio -idm && \
    rm -f initrd"

echo -e "\n- [INFO $(date)] - Remove the old module folder from initrd"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cd initramfs && \
    cd extracted-initrd && \
    cd lib/modules && \
    pwd && \
    rm -rf *"

echo -e "\n- [INFO $(date)] - Add the new module folder in initrd"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cp modules/lib/modules.tar.gz initramfs/extracted-initrd/lib/modules/ && \
    cd initramfs/extracted-initrd/lib/modules/ && \
    tar xf modules.tar.gz && \
    rm -f modules.tar.gz && \
    pwd && \
    ls"

echo -e "\n- [INFO $(date)] - Align kernel configuration in initrd"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cd initramfs && \
    cd extracted-initrd && \
    rm -f ./usr/lib/kernel/config* && \
    rm -f ./usr/lib/kernel/org.clearlinux* && \
    unlink ./usr/lib/kernel/default-native && \
    mv ./usr/lib/kernel/cmdline* ./usr/lib/kernel/cmdline-$(cat /dev/shm/vanilla-linux/version-kernel)-edgefoundation && \
    ls ./usr/lib/kernel/"

echo -e "\n- [INFO $(date)] - Add the new kernel in final folder and initrd"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    rm -rf final-pxe-cl && \
    mkdir -p final-pxe-cl && \
    cd vanilla-linux && \
    cp arch/x86_64/boot/bzImage ../final-pxe-cl/bzImage-$(cat /dev/shm/vanilla-linux/version-kernel)-edgefoundation && \
    ls ../final-pxe-cl && \
    cd initramfs && \
    cd extracted-initrd && \
    cp ../../arch/x86_64/boot/bzImage ./usr/lib/kernel/bzImage-$(cat /dev/shm/vanilla-linux/version-kernel)-edgefoundation && \
    cd ./usr/lib/kernel/ && \
    ln -s bzImage-$(cat /dev/shm/vanilla-linux/version-kernel)-edgefoundation default-native && \
    ls"

echo -e "\n- [INFO $(date)] - Add the new kernel config in initrd"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cp .config initramfs/extracted-initrd/usr/lib/kernel/config-$(cat /dev/shm/vanilla-linux/version-kernel)-edgefoundation && \
    cd initramfs && \
    cd extracted-initrd && \
    ls ./usr/lib/kernel/"

echo -e "\n- [INFO $(date)] - Generate new initrd with all modification"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cd initramfs && \
    cd extracted-initrd && \
    find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initrd && \
    ls ../"

echo -e "\n- [INFO $(date)] - Add the new initrd in final folder"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cd initramfs && \
    cp initrd ../../final-pxe-cl && \
    cd ../../final-pxe-cl && \
    ls"

echo -e "\n- [INFO $(date)] - Create archive with kernel and initrd"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd final-pxe-cl && \
    tar czf ../clearEFx-$(cat /dev/shm/vanilla-linux/clearlinux-version)-pxe.tar.gz . && \
    cd ../ && \
    md5sum clearEFx-$(cat /dev/shm/vanilla-linux/clearlinux-version)-pxe.tar.gz > clearEFx-$(cat /dev/shm/vanilla-linux/clearlinux-version)-pxe.tar.gz.md5sum"

kernel_version=$(cat /dev/shm/vanilla-linux/version-kernel)
clearlinux_version=$(cat /dev/shm/vanilla-linux/clearlinux-version)
config_changed_kernel=$(cat /dev/shm/vanilla-linux/config-changed)

echo -e "\n- [INFO $(date)] - Cleaning environment"
docker exec -i $nextContainer bash -c "cd /dev/shm &&\
    cd vanilla-linux && \
    cd ../ && \
    rm -rf vanilla-linux && \
    rm -rf final-pxe-cl && \
    ls clearEFx*"

echo -e "\n- [INFO $(date)] - Summary"
echo -e "========================================================================" && \
echo -e "========================================================================" && \
echo -e "Kernel Version: $kernel_version                                         " && \
echo -e "Clear Linux Version: $clearlinux_version                                " && \
echo -e "Parameters changed in config kernel:\n$config_changed_kernel            " && \
echo -e "========================================================================" && \
echo -e "========================================================================"
