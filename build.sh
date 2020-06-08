#!/bin/bash
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

if [[ $1 == clean || $1 == c ]]; then
    echo "Building Clean"
    type=clean
elif [[ $1 == dirty || $1 == d ]]; then
    echo "Building Dirty"
    type=dirty
elif [[ $1 == ci ]]; then
    type=ci
else
    echo "Please specify type: clean or dirty"
    exit
fi

setup_env() {
if [ ! -d $CLANG_DIR ]; then
    echo "clang directory does not exists, cloning now..."
    git clone https://github.com/shekhawat2/clang ../clang --depth 1
fi
if [ ! -d $TOOLCHAIN_DIR ]; then
    echo "toolchain directory does not exists, cloning now..."
    git clone https://github.com/shekhawat2/linaro ../tc --depth 1
fi
if [ ! -d $ANYKERNEL_DIR ]; then
    echo "anykernel directory does not exists, cloning now..."
    git clone https://github.com/shekhawat2/AnyKernel3 -b whyredo ../anykernel
fi
if [ ! -d $KERNELBUILDS_DIR ]; then
    echo "builds directory does not exists, cloning now..."
    git clone https://github.com/shekhawat2/kernelbuilds.git ../kernelbuilds
fi
}

export_vars() {
export KERNEL_DIR=${PWD}
export KBUILD_BUILD_USER="Shekhawat2"
export KBUILD_BUILD_HOST="Builder"
export ARCH=arm64
export KERNEL_DIR=${PWD}
export CLANG_DIR=${KERNEL_DIR}/../clang
export TOOLCHAIN_DIR=${KERNEL_DIR}/../tc
export ANYKERNEL_DIR=${KERNEL_DIR}/../anykernel
export KERNELBUILDS_DIR=${KERNEL_DIR}/../kernelbuilds
export JOBS="$(grep -c '^processor' /proc/cpuinfo)"
export PATH=${CLANG_DIR}/bin:${TOOLCHAIN_DIR}/7/bin:${TOOLCHAIN_DIR}/732/bin:${PATH}
export LD_LIBRARY_PATH=${CLANG_DIR}/lib64:$LD_LIBRARY_PATH
}

clean_up() {
echo -e "$cyan Cleaning Up $nocol"
rm -rf out
make clean && make mrproper
}

build_kernel() {
export KBUILD_COMPILER_STRING=$(${CLANG_DIR}/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
BUILD_START=$(date +"%s")
echo -e "$blue Starting $nocol"
make nethunter_defconfig O=out ARCH="${ARCH}"
echo -e "$yellow Making $nocol"
export PATH=${CLANG_DIR}/bin:${PATH}
time make -j"${JOBS}" \
	O=out \
	ARCH=arm64 \
	CC="ccache clang" \
	CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE=aarch64-linux-gnu- \
	CROSS_COMPILE_ARM32=arm-linux-gnueabi-

BUILD_END=$(date +"%s")
DIFF=$((${BUILD_END} - ${BUILD_START}))
echo -e "$yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
}

move_files() {
if [[ ! -e ${KERNEL_DIR}/out/arch/arm64/boot/Image.gz-dtb ]]; then
    echo "build failed"
    exit 1
fi
echo "Movings Files"
cd ${ANYKERNEL_DIR}
rm -rf Image.gz-dtb modules/system/lib/modules/*
git reset --hard HEAD
git checkout whyredo
mv ${KERNEL_DIR}/out/arch/arm64/boot/Image.gz-dtb Image.gz-dtb
find ${KERNEL_DIR}/out -name "*.ko" -exec cp {} modules/system/lib/modules \;
echo -e "$blue Making Zip"
BUILD_TIME=$(date +"%Y%m%d-%T")
zip -r KCUFKernel-whyred-${BUILD_TIME} *
cd ..
mv ${ANYKERNEL_DIR}/KCUFKernel-whyred-${BUILD_TIME}.zip ${KERNELBUILDS_DIR}/KCUFKernel-whyred-${BUILD_TIME}.zip
cd ${KERNEL_DIR}
}

upload_gdrive() {
gdrive upload --share ${KERNELBUILDS_DIR}/KCUFKernel-whyred-${BUILD_TIME}.zip
}

export_vars
setup_env
if [[ $type == clean || $type == ci ]]; then
    clean_up
fi
build_kernel
if [[ $type == clean || $type == ci ]]; then
    move_files
    if [[ $type == clean ]]; then
        upload_gdrive
        clean_up
    elif [[ $type == ci ]]; then
        cd ${KERNELBUILDS_DIR}
        git add -A && git commit -m "${BUILD_TIME}"
        git push https://${GH_TOKEN}@github.com/shekhawat2/kernelbuilds
    fi
fi
