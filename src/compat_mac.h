/* macOS (x86-64, Rosetta 2 on Apple Silicon): the Linux interfaces the runtime uses that
 * Darwin lacks or names differently. Included before every runtime source (-include). */
#ifndef BB_COMPAT_MAC_H
#define BB_COMPAT_MAC_H
#ifdef __APPLE__
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE 1
#endif
#include <stdint.h>
#include <time.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>

#define st_atim st_atimespec
#define st_mtim st_mtimespec
#define st_ctim st_ctimespec
#ifndef MAP_NORESERVE
#define MAP_NORESERVE 0
#endif
#ifndef O_DIRECT
#define O_DIRECT 0
#endif
#ifndef TIMER_ABSTIME
#define TIMER_ABSTIME 1
#endif

/* Darwin names only the calling thread. */
#define pthread_setname_np(thread, name) pthread_setname_np(name)
static inline uint64_t bb_gettid(void) { uint64_t id=0; pthread_threadid_np(NULL,&id); return id; }
#define gettid bb_gettid

/* Not in Darwin's pthreads: polled against the CLOCK_REALTIME deadline. */
int bb_pthread_mutex_timedlock(pthread_mutex_t *mutex, const struct timespec *deadline);
int bb_pthread_rwlock_timedrdlock(pthread_rwlock_t *lock, const struct timespec *deadline);
int bb_pthread_rwlock_timedwrlock(pthread_rwlock_t *lock, const struct timespec *deadline);
#define pthread_mutex_timedlock bb_pthread_mutex_timedlock
#define pthread_rwlock_timedrdlock bb_pthread_rwlock_timedrdlock
#define pthread_rwlock_timedwrlock bb_pthread_rwlock_timedwrlock
int bb_clock_nanosleep(clockid_t clock, int flags, const struct timespec *request, struct timespec *remain);
#define clock_nanosleep bb_clock_nanosleep

/* Darwin's condition variables wait on CLOCK_REALTIME only. */
#define pthread_condattr_setclock(attr, clock) ((void)(attr), (void)(clock), 0)
/* Linux names the runtime uses. */
#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP PTHREAD_RECURSIVE_MUTEX_INITIALIZER
#define CLOCK_REALTIME_COARSE CLOCK_REALTIME
#define RUSAGE_THREAD RUSAGE_SELF /* per-thread times are not available through getrusage */
int bb_getrandom(void *buffer, size_t size, unsigned flags);
#define getrandom bb_getrandom
/* pthread barriers (tests): not in Darwin. */
typedef struct { pthread_mutex_t mutex; pthread_cond_t cond; unsigned count, waiting, cycle; } pthread_barrier_t;
#define PTHREAD_BARRIER_SERIAL_THREAD (-1)
static inline int pthread_barrier_init(pthread_barrier_t *b, const void *attr, unsigned count) {
    (void)attr;
    if (!count) return 22; /* EINVAL */
    b->count=count; b->waiting=0; b->cycle=0;
    pthread_mutex_init(&b->mutex,NULL); pthread_cond_init(&b->cond,NULL);
    return 0;
}
static inline int pthread_barrier_destroy(pthread_barrier_t *b) {
    pthread_cond_destroy(&b->cond); pthread_mutex_destroy(&b->mutex);
    return 0;
}
static inline int pthread_barrier_wait(pthread_barrier_t *b) {
    pthread_mutex_lock(&b->mutex);
    unsigned cycle=b->cycle;
    if (++b->waiting==b->count) {
        b->waiting=0; ++b->cycle;
        pthread_cond_broadcast(&b->cond);
        pthread_mutex_unlock(&b->mutex);
        return PTHREAD_BARRIER_SERIAL_THREAD;
    }
    while (cycle==b->cycle) pthread_cond_wait(&b->cond,&b->mutex);
    pthread_mutex_unlock(&b->mutex);
    return 0;
}
/* Anonymous shared memory object, already unlinked (memfd_create). */
int bb_memfd_create(const char *name);
/* mmap at exactly `address` without replacing an existing mapping (MAP_FIXED_NOREPLACE). */
void *bb_mmap_noreplace(void *address, size_t size, int prot);
/* Closes every descriptor from `first` up (close_range). */
void bb_close_from(int first);
#endif
#endif
