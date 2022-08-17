#!/bin/sh
source "$(pwd)/resources/progress_indicator.sh"

OPENSSL_VERSION="3.0.4"

IOS_MIN_OS_VERSION="15.0"
MACOS_MIN_OS_VERSION="12.0"

PLATFORM_IOS="iOS"
PLATFORM_MACOS="macOS"

# Apple Targets
TARGET_IOS_DEVICE_ARM64="ios-arm64";
TARGET_IOS_SIMULATOR_ARM64="ios-arm64-simulator";
TARGET_IOS_SIMULATOR_X86_64="ios-x86_64-simulator";
TARGET_MACOS_ARM64="macos-arm64";
TARGET_MACOS_X86_64="macos-x86_64";

# XCFramework Targets
XCFRAMEWORK_TARGET_IOS_DEVICE="ios-arm64";
XCFRAMEWORK_TARGET_IOS_SIMULATOR="ios-arm64_x86_64-simulator";
XCFRAMEWORK_TARGET_MACOS="macos-arm64_x86_64";

BASE_DIR="$(pwd)"
BUILD_DIR="$(pwd)/build"
LOGS_PATH="${BUILD_DIR}/logs"
RESOURCES_PATH="${BASE_DIR}/resources"

ALL_TARGETS="${TARGET_IOS_DEVICE_ARM64} ${TARGET_IOS_SIMULATOR_ARM64} ${TARGET_IOS_SIMULATOR_X86_64} ${TARGET_MACOS_ARM64} ${TARGET_MACOS_X86_64}"
ALL_XCFRAMEWORK_TARGETS="${XCFRAMEWORK_TARGET_IOS_DEVICE} ${XCFRAMEWORK_TARGET_IOS_SIMULATOR} ${XCFRAMEWORK_TARGET_MACOS}"
XCFRAMEWORK_PATH="${BASE_DIR}/OpenSSL.xcframework"
export OPENSSL_NO_ENGINE
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
    $TARGET_IOS_DEVICE_ARM64) echo "ios-arm64";;
    $TARGET_IOS_SIMULATOR_ARM64) echo "ios-arm64-simulator";;
    $TARGET_IOS_SIMULATOR_X86_64) echo "ios-x86_64-simulator";;
    $TARGET_MACOS_ARM64) echo "macos-arm64";;
    $TARGET_MACOS_X86_64) echo "darwin64-x86_64";;
esac }

function xcframework_target_dependencies { case "$1" in
    $XCFRAMEWORK_TARGET_IOS_DEVICE) echo "${TARGET_IOS_DEVICE_ARM64}";;
    $XCFRAMEWORK_TARGET_IOS_SIMULATOR) echo "${TARGET_IOS_SIMULATOR_ARM64} ${TARGET_IOS_SIMULATOR_X86_64}";;
    $XCFRAMEWORK_TARGET_MACOS) echo "${TARGET_MACOS_ARM64} ${TARGET_MACOS_X86_64}";;
esac }

function cf_platform { case "$1" in
    $XCFRAMEWORK_TARGET_IOS_DEVICE) echo "iPhoneOS";;
    $XCFRAMEWORK_TARGET_IOS_SIMULATOR) echo "iPhoneSimulator";;
    $XCFRAMEWORK_TARGET_MACOS) echo "MACOSX";;
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
  export OPENSSL_DIR="${BUILD_DIR}/openssl-${OPENSSL_VERSION}-output/${target}"
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
  dependencies_string=( "$(xcframework_target_dependencies $target)" )
  framework_path="${XCFRAMEWORK_PATH}/${target}/OpenSSL.framework"
  mkdir -p "${framework_path}/Headers"
  mkdir -p "${framework_path}/Modules"
  cd $framework_path
  
  dependencies=()
  # Combine static libraries
  for openssl_dep_target in ${dependencies_string}; do
    dependencies+=($openssl_dep_target)
    openssl_lib_path="${BUILD_DIR}/openssl-output/${openssl_dep_target}/lib"
    libtool -static -no_warning_for_no_symbols \
      -o "OpenSSL-${openssl_dep_target}" \
      "${openssl_lib_path}/libcrypto.a" "${openssl_lib_path}/libssl.a"
  done
  
  openssl_path="${BUILD_DIR}/openssl-output/${dependencies[0]}"
  apple_target=${dependencies[0]}
  
  # Lipo together static libraries if target has multiple archs
  if [ "${#dependencies[@]}" == 2 ]; then
    lipo -create \
      "OpenSSL-${dependencies[0]}" \
      "OpenSSL-${dependencies[1]}" \
      -o "OpenSSL"
     
    rm "OpenSSL-${dependencies[0]}"
    rm "OpenSSL-${dependencies[1]}"
  else
    mv "OpenSSL-${dependencies[0]}" "OpenSSL"
  fi
  chmod +x OpenSSL
  
  # Manage Headers
  cp -r ${openssl_path}/include/openssl/* Headers/
  # This header causes a warning if not included, and compile error if included. Just remove it
  rm "Headers/asn1_mac.h" &>/dev/null
  # Fix modular build error: replace <inttypes.h> with <sys/types.h>
  find "Headers" -type f -name "*.h" -exec sed -i "" -e "s/include <inttypes\.h>/include <sys\/types\.h>/g" {} \;
  cp "${RESOURCES_PATH}/OpenSSL.h" "Headers/OpenSSL.h"
  
  # Manage Info.plist
  cp "${RESOURCES_PATH}/Info-framework.plist" "Info.plist"
  /usr/libexec/PlistBuddy -c "Add CFBundleSupportedPlatforms: string $(cf_platform $target)" "Info.plist"
  if [ "$(platform $apple_target)" == $PLATFORM_MACOS ]; then
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $(min_os_version $apple_target)" "Info.plist"
  else
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $(min_os_version $apple_target)" "Info.plist"
  fi
  
  cp "${RESOURCES_PATH}/module.modulemap" "Modules/module.modulemap"
  
  if [ "$(platform $apple_target)" == $PLATFORM_MACOS ]; then
    mkdir -p "Versions/A/Resources"
    mv "OpenSSL" "Headers" "Modules" "Versions/A"
    mv "Info.plist" "Versions/A/Resources"
  
    (cd "Versions" && ln -s "A" "Current")
    ln -s "Versions/Current/OpenSSL"
    ln -s "Versions/Current/Headers"
    ln -s "Versions/Current/Modules"
    ln -s "Versions/Current/Resources"
  fi
}

function build_target { target="${1}"
  build_openssl ${target}
}

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      printf "Usage: build.sh [options]\n\n"
      echo "options:"
      echo "  -h, --help         show help"
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
      progress_end $?
      shift;;
    *)
      printf "Invalid argument ${!#}\n"
      trap - EXIT
      $(pwd)/build-apple.sh --help
      exit
  esac
done

rm -r $XCFRAMEWORK_PATH &>/dev/null
rm -r $LOGS_PATH &>/dev/null
mkdir -p "${LOGS_PATH}"
mkdir -p "${XCFRAMEWORK_PATH}"

cp "${RESOURCES_PATH}/Info-xcframework.plist" "${XCFRAMEWORK_PATH}/Info.plist"

for target in ${ALL_TARGETS}; do
  build_openssl ${target}
done

for target in ${ALL_XCFRAMEWORK_TARGETS}; do
  make_framework ${target}
done

printf "Complete! XCFramework generated at ${XCFRAMEWORK_PATH}\n"
open ${BASE_DIR}
