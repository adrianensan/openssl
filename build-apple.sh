#!/bin/sh
source "$(pwd)/progress_indicator.sh"

OPENSSL_VERSION="1.1.1l"
IOS_MIN_OS_VERSION="12.0"
MACOS_MIN_OS_VERSION="10.12"

PLATFORM_IOS="iOS"
PLATFORM_MACOS="macOS"

# Apple Targets
TARGET_IOS_DEVICE_ARM64="ios-arm64";
TARGET_IOS_SIMULATOR_ARM64="ios-arm64-simulator";
TARGET_IOS_SIMULATOR_X86_64="ios-x86_64-simulator";
TARGET_MACOS_ARM64="macos-arm64";
TARGET_MACOS_X86_64="macos-x86_64";

BASE_DIR="$(pwd)"
BUILD_DIR="$(pwd)/build"
OUTPUT_DIR_BASE="${BUILD_DIR}/output"
LOGS_PATH="${BUILD_DIR}/logs"
INFO_PLIST_PATH="$(pwd)/resources/Info.plist"

PLATFORM=""
TARGETS=""
OUTPUT_DIR=""
XCFRAMEWORK_CREATE_ARGS=""

ORIGINAL_PATH=$PATH

function targets { case "$1" in
  $PLATFORM_APPLE) echo "$(targets ${PLATFORM_IOS}) $(targets ${PLATFORM_MACOS})";;
  $PLATFORM_IOS) echo "${TARGET_IOS_DEVICE_ARM64} ${TARGET_IOS_SIMULATOR_ARM64} ${TARGET_IOS_SIMULATOR_X86_64}";;
  $PLATFORM_MACOS) echo "${TARGET_MACOS_ARM64} ${TARGET_MACOS_X86_64}";;
esac }

function min_os_version {
  case $(platform $1) in
    $PLATFORM_IOS) echo ${IOS_MIN_OS_VERSION};;
    $PLATFORM_MACOS) echo ${MACOS_MIN_OS_VERSION};;
  esac 
}

function config_flags {
  case $(platform $1) in
    $PLATFORM_IOS) echo "-mios-version-min=${IOS_MIN_OS_VERSION}";;
    $PLATFORM_MACOS) echo "-mmacosx-version-min=${MACOS_MIN_OS_VERSION}";;
  esac
}

function openssl_target { case "$1" in
    $TARGET_IOS_DEVICE_ARM64) echo "ios64-xcrun";;
    $TARGET_IOS_SIMULATOR_ARM64) echo "ios-arm64-simulator";;
    $TARGET_IOS_SIMULATOR_X86_64) echo "ios-x86_64-simulator";;
    $TARGET_MACOS_ARM64) echo "darwin64-arm64-cc";;
    $TARGET_MACOS_X86_64) echo "darwin64-x86_64-cc";;
esac }

function platform { case "$1" in
    $TARGET_IOS_DEVICE_ARM64) echo $PLATFORM_IOS;;
    $TARGET_IOS_SIMULATOR_ARM64) echo $PLATFORM_IOS;;
    $TARGET_IOS_SIMULATOR_X86_64) echo $PLATFORM_IOS;;
    $TARGET_MACOS_ARM64) echo $PLATFORM_MACOS;;
    $TARGET_MACOS_X86_64) echo $PLATFORM_MACOS;;
esac }

function name { case "$1" in
    $TARGET_IOS_DEVICE_ARM64) echo "iOS (arm64)";;
    $TARGET_IOS_SIMULATOR_ARM64) echo "iOS Simulator (Apple Silicon)";;
    $TARGET_IOS_SIMULATOR_X86_64) echo "iOS Simulator (Intel)";;
    $TARGET_MACOS_ARM64) echo "macOS (Apple Silicon)";;
    $TARGET_MACOS_X86_64) echo "macOS (Intel)";;
esac }

function build_openssl { target="${1}"
  export OPENSSL_DIR="${BUILD_DIR}/openssl-output/${target}"
  export OPENSSL_LIB_DIR=${OPENSSL_DIR}
  export OPENSSL_INCLUDE_DIR=${OPENSSL_DIR}/include

  if [ ! -f "${OPENSSL_DIR}/lib/libcrypto.a" ]; then
    rm -rf "${OPENSSL_DIR}" &>/dev/null
    mkdir -p "${OPENSSL_DIR}"

    openssl_tar_name="openssl-${OPENSSL_VERSION}.tar.gz"

    if [ ! -f "${BUILD_DIR}/openssl-${OPENSSL_VERSION}" ]; then
      if [ ! -f "${BUILD_DIR}/${openssl_tar_name}" ]; then
        progress_show "Downloading OpenSSL"
        curl -o "${BUILD_DIR}/${openssl_tar_name}" \
             -k "https://www.openssl.org/source/${openssl_tar_name}" \
             &> "${LOGS_PATH}/download-openssl-${OPENSSL_VERSION}.log"
        progress_end $?
      fi
      tar xf "${BUILD_DIR}/${openssl_tar_name}" -C "${BUILD_DIR}"
    fi
    progress_show "Configuring OpenSSL for $(name $target)"
    cd "${BUILD_DIR}/openssl-${OPENSSL_VERSION}"
    
    cp "${BASE_DIR}/resources/configs/apple.conf" "./Configurations/20-apple.conf"

    make clean &>/dev/null
    ./Configure $(openssl_target ${target}) \
      --prefix="${OPENSSL_DIR}" \
      --openssldir="${OPENSSL_DIR}" \
      $(config_flags ${target}) \
      &> "${LOGS_PATH}/openssl-${OPENSSL_VERSION}-configure-${target}.log"
    progress_end $?

    progress_show "Building OpenSSL for $(name $target)"
    make &> "${LOGS_PATH}/openssl-${OPENSSL_VERSION}-make-${target}.log"
    make install &> "${LOGS_PATH}/openssl-${OPENSSL_VERSION}-make-install-${target}.log"
    progress_end $?
  fi
}

function make_framework { target="${1}"
  openssl_path="${BUILD_DIR}/openssl-output/${target}"
  framework_path="${OUTPUT_DIR}/frameworks/${target}/OpenSSL.framework"
  mkdir -p "${framework_path}/Headers"
  libtool -static -no_warning_for_no_symbols \
    -o ${framework_path}/OpenSSL \
    "${openssl_path}/lib/libcrypto.a" "${openssl_path}/lib/libssl.a"
  cp -r ${openssl_path}/include/openssl/* ${framework_path}/Headers/
  cp $INFO_PLIST_PATH ${framework_path}/Info.plist
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $(min_os_version $target)" ${framework_path}/Info.plist
  
  if [ "$(platform $target)" == $PLATFORM_MACOS ]; then
    cd $framework_path
    mkdir "Versions"
    mkdir "Versions/A"
    mkdir "Versions/A/Resources"
    mv "OpenSSL" "Headers" "Versions/A"
    mv "Info.plist" "Versions/A/Resources"
  
    (cd "Versions" && ln -s "A" "Current")
    ln -s "Versions/Current/OpenSSL"
    ln -s "Versions/Current/Headers"
    ln -s "Versions/Current/Resources"
  fi
  
  XCFRAMEWORK_CREATE_ARGS+="-framework ${framework_path} "
}

function make_xcframework { target="${1}"
  openssl_path="${BUILD_DIR}/openssl-output/${target}"
  framework_path="${XCFRAMEWORK_PATH}/${target}"
  mkdir -p "${framework_path}/Headers/openssl"
  libtool -static -no_warning_for_no_symbols \
    -o ${framework_path}/OpenSSL.a \
    "${openssl_path}/lib/libcrypto.a" "${openssl_path}/lib/libssl.a"
  cp -r ${openssl_path}/include/openssl/* ${framework_path}/Headers/openssl/
}

function build_target { target="${1}"
  build_openssl ${target}
  make_xcframework ${target}

  PATH=$ORIGINAL_PATH
}

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      printf "Usage: build.sh platform [options]\n\n"
      echo "platform: apple|ios|macos"
      echo "options:"
      echo "  -h, --help         show help"
      echo "  -v, --verbose      verbose output"
      echo "  --clean            build from scratch"
      echo "  --clean-full       build from scratch, and clear output and downloads"
      exit 0;;
    --clean)
      progress_show "Cleaning up"
      rm -rf "target" &>/dev/null
      #rm -rf "${NDK_TOOLCHAIN_DIR}" &>/dev/null
      rm -rf "${BUILD_DIR}" &>/dev/null
      progress_end $?
      shift;;
    --clean-full)
      progress_show "Cleaning up"
      rm -rf "target" &>/dev/null
      rm -rf "${BUILD_DIR}" &>/dev/null
      rm -rf "${OUTPUT_DIR_BASE}" &>/dev/null
      progress_end $?
      shift;;
    -v|--verbose) OUTPUT=/dev/tty; shift;;
    *)
      printf "Invalid argument ${!#}\n"
      trap - EXIT
      $(pwd)/build-apple.sh --help
      exit
  esac
done

if [ -z "${PLATFORM}" ]; then
  printf "Invalid argument ${!#}\n"
  trap - EXIT
  $(pwd)/build.sh --help
  exit
fi

TARGETS="$(targets ${PLATFORM})"
OUTPUT_DIR="${OUTPUT_DIR_BASE}/${PLATFORM}"
export XCFRAMEWORK_PATH="${OUTPUT_DIR}/OpenSSL.xcframework"
rm -r $OUTPUT_DIR &>/dev/null
rm -r $LOGS_PATH &>/dev/null
mkdir -p "${LOGS_PATH}"
mkdir -p "${OUTPUT_DIR}"

mkdir -p "${XCFRAMEWORK_PATH}"
cp $INFO_PLIST_PATH "${OUTPUT_DIR}/OpenSSL.xcframework/Info.plist"

echo $TARGETS
for target in ${TARGETS}; do
  build_target ${target}
done

mkdir -p "${OUTPUT_DIR}/OpenSSL.xcframework/macos-arm64_x86_64"
cp -r "${OUTPUT_DIR}/OpenSSL.xcframework/macos-arm64/Headers" \
      "${OUTPUT_DIR}/OpenSSL.xcframework/macos-arm64_x86_64/Headers"
lipo -create \
     "${OUTPUT_DIR}/OpenSSL.xcframework/macos-arm64/OpenSSL.a" \
     "${OUTPUT_DIR}/OpenSSL.xcframework/macos-x86_64/OpenSSL.a" \
     -o "${OUTPUT_DIR}/OpenSSL.xcframework/macos-arm64_x86_64/OpenSSL.a"
     
rm -r "${OUTPUT_DIR}/OpenSSL.xcframework/macos-arm64"
rm -r "${OUTPUT_DIR}/OpenSSL.xcframework/macos-x86_64"
     
# mkdir -p "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator"
# cp -r "${OUTPUT_DIR}/OpenSSL.xcframework/ios-x86_64-simulator/Headers" \
#       "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator/Headers"
# cp -r "${OUTPUT_DIR}/OpenSSL.xcframework/ios-x86_64-simulator/OpenSSL.a" \
#       "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator/OpenSSL.a"
      
#rm -r "${OUTPUT_DIR}/OpenSSL.xcframework/ios-x86_64-simulator"
#rm -r "${OUTPUT_DIR}/OpenSSL.xcframework/macos-x86_64"
     
mkdir -p "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator"
cp -r "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64-simulator/Headers" \
      "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator/Headers"
lipo -create \
     "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64-simulator/OpenSSL.a" \
     "${OUTPUT_DIR}/OpenSSL.xcframework/ios-x86_64-simulator/OpenSSL.a" \
     -o "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator/OpenSSL.a"
     
lipo -info "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64_x86_64-simulator/OpenSSL.a"
rm -r "${OUTPUT_DIR}/OpenSSL.xcframework/ios-arm64-simulator"
rm -r "${OUTPUT_DIR}/OpenSSL.xcframework/ios-x86_64-simulator"

#xcodebuild -create-xcframework $XCFRAMEWORK_CREATE_ARGS -output "${OUTPUT_DIR}/OpenSSL.xcframework"

printf "Complete! The libraries is located in ${OUTPUT_DIR}\n"
open ${OUTPUT_DIR}
