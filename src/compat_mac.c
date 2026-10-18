/* macOS replacements for Linux interfaces (compat_mac.h). */
#ifdef __APPLE__
#include "compat_mac.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/resource.h>

#undef pthread_mutex_timedlock
#undef pthread_rwlock_timedrdlock
#undef pthread_rwlock_timedwrlock
#undef clock_nanosleep

static int passed(const struct timespec *deadline) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME,&now);
    return now.tv_sec>deadline->tv_sec || (now.tv_sec==deadline->tv_sec && now.tv_nsec>=deadline->tv_nsec);
}
static void pause_briefly(void) { struct timespec t={0,50000}; nanosleep(&t,NULL); }
#define POLL_UNTIL(attempt) \
    for (;;) { int e=(attempt); if (e!=EBUSY) return e; if (passed(deadline)) return ETIMEDOUT; pause_briefly(); }

int bb_pthread_mutex_timedlock(pthread_mutex_t *mutex, const struct timespec *deadline) {
    POLL_UNTIL(pthread_mutex_trylock(mutex))
}
int bb_pthread_rwlock_timedrdlock(pthread_rwlock_t *lock, const struct timespec *deadline) {
    POLL_UNTIL(pthread_rwlock_tryrdlock(lock))
}
int bb_pthread_rwlock_timedwrlock(pthread_rwlock_t *lock, const struct timespec *deadline) {
    POLL_UNTIL(pthread_rwlock_trywrlock(lock))
}
int bb_clock_nanosleep(clockid_t clock, int flags, const struct timespec *request, struct timespec *remain) {
    struct timespec wait=*request;
    if (flags & TIMER_ABSTIME) {
        struct timespec now;
        clock_gettime(clock,&now);
        int64_t ns=(int64_t)(request->tv_sec-now.tv_sec)*1000000000+(request->tv_nsec-now.tv_nsec);
        if (ns<=0) return 0;
        wait=(struct timespec){(time_t)(ns/1000000000),(long)(ns%1000000000)};
        remain=NULL;
    }
    return nanosleep(&wait,remain) ? errno : 0;
}

int bb_getrandom(void *buffer, size_t size, unsigned flags) {
    (void)flags;
    arc4random_buf(buffer,size);
    return (int)size;
}
int bb_memfd_create(const char *name) {
    char path[64];
    for (unsigned attempt=0; attempt<100; ++attempt) {
        snprintf(path,sizeof(path),"/bb-%d-%u-%s",(int)getpid(),attempt,name);
        path[31]=0; /* PSHMNAMLEN */
        int fd=shm_open(path,O_RDWR|O_CREAT|O_EXCL,0600);
        if (fd>=0) { shm_unlink(path); fcntl(fd,F_SETFD,FD_CLOEXEC); return fd; }
        if (errno!=EEXIST) return -1;
    }
    return -1;
}
void *bb_mmap_noreplace(void *address, size_t size, int prot) {
    void *p=mmap(address,size,prot,MAP_PRIVATE|MAP_ANON,-1,0);
    if (p==MAP_FAILED) return MAP_FAILED;
    if (p!=address) { munmap(p,size); errno=EEXIST; return MAP_FAILED; }
    return p;
}
void bb_close_from(int first) {
    struct rlimit limit;
    int last=getrlimit(RLIMIT_NOFILE,&limit) || limit.rlim_cur>65536 ? 65536 : (int)limit.rlim_cur;
    for (int fd=first; fd<last; ++fd) close(fd);
}
#endif
