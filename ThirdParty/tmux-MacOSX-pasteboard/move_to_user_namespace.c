#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <dlfcn.h>
#include <mach/mach.h>

#include "msg.h"

#define FIND_SYMBOL(NAME, RET, SIG) \
    static const char fn_ ## NAME [] = # NAME; \
    typedef RET (*ft_ ## NAME) SIG; \
    ft_ ## NAME f_ ## NAME; \
    if (!(f_ ## NAME = (ft_ ## NAME)dlsym(RTLD_NEXT, fn_ ## NAME))) { \
        warn("unable to find %s: %s", fn_ ## NAME, dlerror()); \
        return -1; \
    }

static int move_to_user_namespace__100500(void)
{
    FIND_SYMBOL(_vprocmgr_move_subset_to_user, void *, (uid_t, const char *))

    if (f__vprocmgr_move_subset_to_user(getuid(), "Background") != NULL) {
        warn("%s failed", fn__vprocmgr_move_subset_to_user);
        return -1;
    }

    return 0;
}

static int move_to_user_namespace__100600(void)
{
    FIND_SYMBOL(_vprocmgr_move_subset_to_user, void *, (uid_t, const char *, uint64_t))

    if (f__vprocmgr_move_subset_to_user(getuid(), "Background", 0) != NULL) {
        warn("%s failed", fn__vprocmgr_move_subset_to_user);
        return -1;
    }

    return 0;
}

static int move_to_user_namespace__101000(void)
{
    mach_port_t puc = MACH_PORT_NULL;
    mach_port_t rootbs = MACH_PORT_NULL;

    FIND_SYMBOL(bootstrap_get_root, kern_return_t, (mach_port_t, mach_port_t *))
    FIND_SYMBOL(bootstrap_look_up_per_user, kern_return_t, (mach_port_t, const char *, uid_t, mach_port_t *))

    if (f_bootstrap_get_root(bootstrap_port, &rootbs) != KERN_SUCCESS) {
        warn("%s failed", fn_bootstrap_get_root);
        return -1;
    }
    if (f_bootstrap_look_up_per_user(rootbs, NULL, getuid(), &puc) != KERN_SUCCESS) {
        warn("%s failed", fn_bootstrap_look_up_per_user);
        return -1;
    }

    if (task_set_bootstrap_port(mach_task_self(), puc) != KERN_SUCCESS) {
        warn("task_set_bootstrap_port failed");
        return -1;
    }
    if (mach_port_deallocate(mach_task_self(), bootstrap_port) != KERN_SUCCESS) {
        warn("mach_port_deallocate failed");
        return -1;
    }

    bootstrap_port = puc;

    return 0;
}

int move_to_user_namespace(unsigned int os)
{
    switch (os) {
    case 100500:
        return move_to_user_namespace__100500();

    case 100600:
        return move_to_user_namespace__100600();

    case 101000:
        return move_to_user_namespace__101000();

    default:
        return -1;
    }
}
