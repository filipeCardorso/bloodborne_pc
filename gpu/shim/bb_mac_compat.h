// SPDX-License-Identifier: GPL-2.0-or-later
// bbport (macOS): the Linux thread identity call the renderer uses for diagnostics.
// Force-included into the GPU library on macOS only (CMakeLists.txt).
#pragma once
#ifdef __APPLE__
#include <pthread.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
static inline int gettid(void) {
    uint64_t id = 0;
    pthread_threadid_np(NULL, &id);
    return (int)id;
}
#ifdef __cplusplus
}
#endif
#endif
