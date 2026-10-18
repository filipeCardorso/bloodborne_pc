/* macOS: the guest's TCB load (`mov rax, gs:[disp32]`, rewritten by probe.c's patch_tcb_loads)
 * reads the TCB that runtime_thread.c stored in the pthread TSD slot, on every thread. */
#include "runtime.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

void runtime_restart(void) {}
uint32_t runtime_thread_tcb_offset(void);
typedef uint64_t (*Load)(void);
static Load load;

static void *check(void *name) {
    runtime_thread_attach_host(name);
    const uint64_t tcb = load();
    assert(tcb && *(uint64_t *)(uintptr_t)tcb == tcb); /* tcb_self */
    printf("%s: guest TCB %#llx\n", (const char *)name, (unsigned long long)tcb);
    return (void *)(uintptr_t)tcb;
}

int main(void) {
    runtime_start(1);
    /* The 9-byte load as the loader leaves it in guest code, followed by ret. */
    unsigned char code[] = {0x65, 0x48, 0x8b, 0x04, 0x25, 0, 0, 0, 0, 0xc3};
    const uint32_t displacement = runtime_thread_tcb_offset();
    memcpy(code + 5, &displacement, 4);
    unsigned char *page = runtime_low_map(16384, PROT_READ | PROT_WRITE);
    assert(page);
    memcpy(page, code, sizeof(code));
    assert(!mprotect(page, 16384, PROT_READ | PROT_EXEC));
    load = (Load)page;
    void *main_tcb = check("main");
    pthread_t other;
    void *other_tcb = NULL;
    assert(!pthread_create(&other, NULL, check, "thread"));
    assert(!pthread_join(other, &other_tcb));
    assert(main_tcb != other_tcb);
    printf("PASS: guest TCB loads through gs:[0x%x] (low map %p)\n", displacement, (void *)page);
    return 0;
}
