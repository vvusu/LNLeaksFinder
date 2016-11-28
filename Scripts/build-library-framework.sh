set -e

# If we're already inside this script then die
if [ -n "$RW_MULTIPLATFORM_BUILD_IN_PROGRESS" ]; then
exit 0
fi
export RW_MULTIPLATFORM_BUILD_IN_PROGRESS=1

RW_FRAMEWORK_NAME=${PROJECT_NAME}
RW_INPUT_STATIC_LIB="lib${PROJECT_NAME}.a"
RW_FRAMEWORK_LOCATION="${BUILT_PRODUCTS_DIR}/${RW_FRAMEWORK_NAME}.framework"

function build_static_library {
# Will rebuild the static library as specified
#     build_static_library sdk
xcrun xcodebuild -project "${PROJECT_FILE_PATH}" \
-target "${TARGET_NAME}" \
-configuration "${CONFIGURATION}" \
-sdk "${1}" \
ONLY_ACTIVE_ARCH=NO \
BUILD_DIR="${BUILD_DIR}" \
OBJROOT="${OBJROOT}" \
BUILD_ROOT="${BUILD_ROOT}" \
SYMROOT="${SYMROOT}" $ACTION
}

function make_fat_library {
# Will smash 2 static libs together
#     make_fat_library in1 in2 out
xcrun lipo -create "${1}" "${2}" -output "${3}"
}

# 1 - Extract the platform (iphoneos/iphonesimulator) from the SDK name
if [[ "$SDK_NAME" =~ ([A-Za-z]+) ]]; then
RW_SDK_PLATFORM=${BASH_REMATCH[1]}
else
echo "Could not find platform name from SDK_NAME: $SDK_NAME"
exit 1
fi

# 2 - Extract the version from the SDK
if [[ "$SDK_NAME" =~ ([0-9]+.*$) ]]; then
RW_SDK_VERSION=${BASH_REMATCH[1]}
else
echo "Could not find sdk version from SDK_NAME: $SDK_NAME"
exit 1
fi

# 3 - Determine the other platform
if [ "$RW_SDK_PLATFORM" == "iphoneos" ]; then
RW_OTHER_PLATFORM=iphonesimulator
else
RW_OTHER_PLATFORM=iphoneos
fi

# 4 - Find the build directory
if [[ "$BUILT_PRODUCTS_DIR" =~ (.*)$RW_SDK_PLATFORM$ ]]; then
RW_OTHER_BUILT_PRODUCTS_DIR="${BASH_REMATCH[1]}${RW_OTHER_PLATFORM}"
else
echo "Could not find other platform build directory."
exit 1
fi

# Build the other platform.
build_static_library "${RW_OTHER_PLATFORM}${RW_SDK_VERSION}"

# If we're currently building for iphonesimulator, then need to rebuild
#   to ensure that we get both i386 and x86_64
if [ "$RW_SDK_PLATFORM" == "iphonesimulator" ]; then
build_static_library "${SDK_NAME}"
fi

# Join the 2 static libs into 1 and push into the .framework
make_fat_library "${BUILT_PRODUCTS_DIR}/${RW_INPUT_STATIC_LIB}" \
"${RW_OTHER_BUILT_PRODUCTS_DIR}/${RW_INPUT_STATIC_LIB}" \
"${RW_FRAMEWORK_LOCATION}/Versions/A/${RW_FRAMEWORK_NAME}"

# Ensure that the framework is present in both platform's build directories
cp -a "${RW_FRAMEWORK_LOCATION}/Versions/A/${RW_FRAMEWORK_NAME}" \
"${RW_OTHER_BUILT_PRODUCTS_DIR}/${RW_FRAMEWORK_NAME}.framework/Versions/A/${RW_FRAMEWORK_NAME}"

# Copy the framework to the user's desktop
ditto "${RW_FRAMEWORK_LOCATION}" "${HOME}/Desktop/${RW_FRAMEWORK_NAME}.framework"

# Copy the resources bundle to the user's desktop
ditto "${BUILT_PRODUCTS_DIR}/${RW_FRAMEWORK_NAME}.bundle" \
"${HOME}/Desktop/${RW_FRAMEWORK_NAME}.bundle"
