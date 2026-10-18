#!/usr/bin/env bash
# macOS: builds out/bb-probe (x86-64; runs through Rosetta 2 on Apple Silicon) against the
# dependencies from packaging/macos/build_deps.sh.
# Usage: bash packaging/macos/build.sh   (BB_MAC_DEPS: dependency prefix, default .deps-macos)
set -euo pipefail
cd -- "$(dirname -- "$0")/../.."
deps=$(cd "${BB_MAC_DEPS:-.deps-macos}" && pwd)
# pkg-config output is split at spaces: "Application Support" and the like break the build.
[[ $deps != *" "* && $PWD != *" "* ]] || { echo "The checkout and $deps need a path without spaces." >&2; exit 1; }
[[ -f $deps/.done-ffmpeg ]] || { echo "Run packaging/macos/build_deps.sh first." >&2; exit 1; }
for tool in cmake ninja pkg-config glslang; do
    command -v "$tool" >/dev/null || { echo "Need $tool: brew install cmake ninja pkgconf glslang nasm boost" >&2; exit 1; }
done
if [[ ! -f gpu/third_party/fsr-vulkan/CMakeLists.txt || ! -f gpu/third_party/imgui/imgui.h ]]; then
    git submodule update --init --recursive
fi
for patch in gpu/patches/fsr-vulkan/*.patch; do
    if ! git -C gpu/third_party/fsr-vulkan apply --reverse --check "$PWD/$patch" 2>/dev/null; then
        git -C gpu/third_party/fsr-vulkan apply "$PWD/$patch"
    fi
done
export PKG_CONFIG_PATH=$deps/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$deps/lib/pkgconfig:$deps/share/pkgconfig
boost=$(brew --prefix boost 2>/dev/null || true)
mkdir -p out
cmake -S gpu -B out/gpu -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBB_PGO=off -DBB_LTO="${BB_LTO:-OFF}" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_SYSTEM_PROCESSOR=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 \
    -DCMAKE_PREFIX_PATH="$deps" -DBoost_INCLUDE_DIR="$boost/include" -DBoost_ROOT="$boost" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null
if ! ninja -k "${BB_KEEP_GOING:-1}" -C out/gpu bb-probe bb-gpu-capabilities > out/gpu-build.log 2>&1; then
    grep -E 'error:|FAILED|Undefined|ld: ' out/gpu-build.log | sed "s|$PWD/||g" | sort -u | head -60 >&2
    echo 'Build failed (full log: out/gpu-build.log)' >&2; exit 1
fi
cp out/gpu/bb-probe out/gpu/bb-gpu-capabilities out/
# Self-contained out/: the Vulkan loader, SDL3 and MoltenVK sit next to the executables, and
# the renderer points the loader at that directory (VK_DRIVER_FILES, vk_platform.cpp).
cp "$deps/lib/libvulkan.1.dylib" "$deps/lib/libSDL3.0.dylib" "$deps/lib/libMoltenVK.dylib" out/
sed 's|"library_path": ".*"|"library_path": "./libMoltenVK.dylib"|' \
    "$deps/share/vulkan/icd.d/MoltenVK_icd.json" > out/MoltenVK_icd.json
for binary in out/bb-probe out/bb-gpu-capabilities; do
    install_name_tool -add_rpath @executable_path "$binary" 2>/dev/null || true
    codesign --force -s - "$binary" 2>/dev/null
done
echo "Built $PWD/out/bb-probe"
