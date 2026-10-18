# Bloodborne on macOS (experimental)

The game's own x86-64 code runs natively, so on Apple Silicon the whole process is an x86-64
binary run by **Rosetta 2**, and the renderer's Vulkan goes to Metal through **MoltenVK**.
Intel Macs run the same build directly.

Status: builds, and everything that runs without game files passes (Vulkan through MoltenVK,
the runtime's memory, mutex and semaphore tests, and the guest TCB loads through `gs`). The game
itself has not been started yet.

## Build

You need macOS 15 or newer (Rosetta 2 runs AVX from macOS 15) with the Xcode Command Line Tools and Homebrew. Clone into a path
**without spaces**, because pkg-config splits paths at spaces.

```bash
brew install cmake ninja pkgconf nasm glslang boost
git clone --recursive -b macos-port https://github.com/filipeCardorso/bloodborne_pc.git ~/bloodborne_pc
cd ~/bloodborne_pc
bash packaging/macos/build_deps.sh   # x86-64 libraries into .deps-macos (about 20 minutes, 2 GB)
bash build.sh                        # out/bb-probe and the dylibs next to it
```

## Run

You need your own decrypted dump of Bloodborne (CUSA03173, version 1.09). It is about 30 GB
and can sit on an external drive.

```bash
BB_GAME_DIR=/Volumes/External/CUSA03173 bash run.sh
```

If it stops, send `run.sh`'s output. Its last lines say where it stopped.

## What differs from Linux

- **Address space.** Apple Silicon reserves [64 GiB, 448 GiB) for the GPU (XNU's GPU carveout),
  so nothing can be mapped there, not even through Rosetta. The PS4 user range therefore starts
  at `0x7000000000` instead of `0x1000000000`, which still fits the 40-bit GPU addresses. The
  loader's low area (image, stacks, trampolines) stays at [32 GiB, 64 GiB).
- **Guest TCB.** As on Windows, GS cannot be moved: it points at the thread's pthread TSD slots.
  The guest TCB lives in one slot, and the loader rewrites `mov rax, fs:[0]` into
  `mov rax, gs:[8*key]` (`patch_tcb_loads`).
- **CPU check.** Rosetta 2 runs AVX, AVX2, BMI1, LZCNT, MOVBE, FMA and F16C, but its CPUID
  reports none of them. The check is skipped under Rosetta, and the Legacy CPU translations stay
  off.
- **Guest memory pool.** The pool is an unlinked POSIX shared memory object rather than a memfd.
  Darwin cannot punch holes in it, so released pages are cleared with memset.
- **Linux interfaces.** `src/compat_mac.h` (C runtime) and `gpu/shim/bb_mac_compat.h` (renderer)
  provide timed locks, `clock_nanosleep`, barriers, `gettid` and similar calls.

## Known gaps

- Host heap objects handed to the game (thread records, TLS blocks) come from macOS malloc above
  1 TiB. Linux keeps them below 1 TiB with `mallopt`, while Windows does not either.
- DLSS and FSR 4 are not available. FSR 3.1 and TAA build.
- No launcher app yet: `run.sh` is the way to start the game.
