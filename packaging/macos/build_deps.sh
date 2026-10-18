#!/usr/bin/env bash
# macOS (Apple Silicon or Intel): builds the x86-64 dependencies of bb-probe into one prefix.
# The game's code is x86-64 and runs natively, so on Apple Silicon the whole process is an
# x86-64 binary run by Rosetta 2; Homebrew no longer ships Intel bottles, so the libraries are
# built from source here. Host tools (cmake, ninja, pkgconf, nasm) and the header-only Boost
# come from the normal Homebrew: brew install cmake ninja pkgconf nasm boost
# Usage: bash packaging/macos/build_deps.sh [prefix]   (default: .deps-macos)
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
prefix=$(mkdir -p "${1:-.deps-macos}" && cd "${1:-.deps-macos}" && pwd)
src=$prefix/src
# pkg-config output is split at spaces: "Application Support" and the like break the build.
[[ $prefix != *" "* && $PWD != *" "* ]] || { echo "The checkout and $prefix need a path without spaces." >&2; exit 1; }
mkdir -p "$src"
jobs=$(sysctl -n hw.ncpu)
export MACOSX_DEPLOYMENT_TARGET=13.0
export PKG_CONFIG_PATH=$prefix/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$prefix/lib/pkgconfig:$prefix/share/pkgconfig

cmake_common=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_SYSTEM_PROCESSOR=x86_64
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET -DCMAKE_INSTALL_PREFIX="$prefix"
    -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_FIND_ROOT_PATH="$prefix" -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

# fetch <name> <git url> <tag>: shallow clone once.
fetch() {
    if [[ ! -d $src/$1 ]]; then
        git clone -q --depth 1 --recurse-submodules --shallow-submodules -b "$3" "$2" "$src/$1"
    fi
}
# cmake_build <name> [cmake args...]: configure, build and install, once.
cmake_build() {
    local name=$1; shift
    [[ -f $prefix/.done-$name ]] && return
    echo "== $name"
    cmake -S "$src/$name" -B "$src/$name/build-x86" "${cmake_common[@]}" "$@" >/dev/null
    ninja -C "$src/$name/build-x86" install >/dev/null
    touch "$prefix/.done-$name"
}

fetch Vulkan-Headers https://github.com/KhronosGroup/Vulkan-Headers.git vulkan-sdk-1.4.363.0
cmake_build Vulkan-Headers
fetch Vulkan-Loader https://github.com/KhronosGroup/Vulkan-Loader.git vulkan-sdk-1.4.363.0
cmake_build Vulkan-Loader -DVULKAN_HEADERS_INSTALL_DIR="$prefix" -DBUILD_TESTS=OFF

# MoltenVK (Vulkan on Metal): the release's universal dylib and its loader manifest. Like
# shadPS4's macOS builds it is listed as a regular driver (no portability enumeration needed).
if [[ ! -f $prefix/.done-MoltenVK ]]; then
    echo "== MoltenVK"
    curl -fsSL -o "$src/MoltenVK-macos.tar" \
        https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar
    tar -xf "$src/MoltenVK-macos.tar" -C "$src"
    rm "$src/MoltenVK-macos.tar"
    mkdir -p "$prefix/lib" "$prefix/share/vulkan/icd.d"
    cp "$src/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$prefix/lib/"
    cat > "$prefix/share/vulkan/icd.d/MoltenVK_icd.json" <<'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "../../../lib/libMoltenVK.dylib",
        "api_version": "1.4.0",
        "is_portability_driver": false
    }
}
EOF
    touch "$prefix/.done-MoltenVK"
fi

fetch SDL https://github.com/libsdl-org/SDL.git release-3.4.18
cmake_build SDL -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
fetch fmt https://github.com/fmtlib/fmt.git 12.2.0
cmake_build fmt -DFMT_TEST=OFF -DFMT_DOC=OFF
fetch zydis https://github.com/zyantific/zydis.git v4.1.1
# Zycore is installed on its own so that Zydis' CMake package finds it.
if [[ ! -f $prefix/.done-zycore ]]; then
    echo "== zycore"
    cmake -S "$src/zydis/dependencies/zycore" -B "$src/zydis/build-zycore" "${cmake_common[@]}" >/dev/null
    ninja -C "$src/zydis/build-zycore" install >/dev/null
    touch "$prefix/.done-zycore"
fi
cmake_build zydis -DZYDIS_BUILD_TOOLS=OFF -DZYDIS_BUILD_EXAMPLES=OFF -DZYDIS_BUILD_DOXYGEN=OFF
fetch xxHash https://github.com/Cyan4973/xxHash.git v0.8.4
if [[ ! -f $prefix/.done-xxHash ]]; then
    echo "== xxHash"
    cmake -S "$src/xxHash/build/cmake" -B "$src/xxHash/build-x86" "${cmake_common[@]}" \
        -DBUILD_SHARED_LIBS=OFF -DXXHASH_BUILD_XXHSUM=OFF >/dev/null
    ninja -C "$src/xxHash/build-x86" install >/dev/null
    touch "$prefix/.done-xxHash"
fi
fetch robin-map https://github.com/Tessil/robin-map.git v1.4.1
cmake_build robin-map
fetch VulkanMemoryAllocator https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git v3.4.0
cmake_build VulkanMemoryAllocator
fetch json https://github.com/nlohmann/json.git v3.12.0
cmake_build json -DJSON_BuildTests=OFF
fetch protobuf https://github.com/protocolbuffers/protobuf.git v36.2
cmake_build protobuf -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_ABSL_PROVIDER=module \
    -Dprotobuf_BUILD_SHARED_LIBS=OFF -DABSL_PROPAGATE_CXX_STD=ON -Dprotobuf_BUILD_LIBUPB=OFF
# The installed absl/base/options.h says "never std::string_view" although the libraries were
# built with it: "detect" (2) makes C++17 code match them (else ParseFromString is undefined).
sed -i '' -E 's/^#define (ABSL_OPTION_USE_STD_[A-Z_]+) 0$/#define \1 2/' "$prefix/include/absl/base/options.h"

fetch miniupnp https://github.com/miniupnp/miniupnp.git miniupnpc_2_3_3
if [[ ! -f $prefix/.done-miniupnpc ]]; then
    echo "== miniupnpc"
    cmake -S "$src/miniupnp/miniupnpc" -B "$src/miniupnp/build-x86" "${cmake_common[@]}" \
        -DUPNPC_BUILD_SHARED=OFF -DUPNPC_BUILD_TESTS=OFF -DUPNPC_BUILD_SAMPLE=OFF >/dev/null
    ninja -C "$src/miniupnp/build-x86" install >/dev/null
    touch "$prefix/.done-miniupnpc"
fi

fetch openssl https://github.com/openssl/openssl.git openssl-4.0.3
if [[ ! -f $prefix/.done-openssl ]]; then
    echo "== openssl"
    (cd "$src/openssl" && ./Configure darwin64-x86_64-cc no-shared no-tests no-docs \
        --prefix="$prefix" --libdir=lib >/dev/null && make -j"$jobs" >/dev/null && make install_sw >/dev/null)
    touch "$prefix/.done-openssl"
fi

# FFmpeg: only what the game's movies need (H.264 and AAC in MP4).
fetch ffmpeg https://github.com/FFmpeg/FFmpeg.git n7.1.2
if [[ ! -f $prefix/.done-ffmpeg ]]; then
    echo "== ffmpeg"
    (cd "$src/ffmpeg" && ./configure --prefix="$prefix" --arch=x86_64 --enable-cross-compile \
        --target-os=darwin --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64" \
        --extra-cflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        --extra-ldflags="-arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        --disable-everything --disable-programs --disable-doc --disable-network --disable-autodetect \
        --enable-static --disable-shared --enable-swscale --enable-swresample \
        --enable-decoder=h264,aac,aac_latm,mp3,pcm_s16le --enable-parser=h264,aac \
        --enable-demuxer=mov,h264,aac --enable-protocol=file,pipe >/dev/null &&
        make -j"$jobs" >/dev/null && make install >/dev/null)
    touch "$prefix/.done-ffmpeg"
fi

echo "Dependencies in $prefix"
