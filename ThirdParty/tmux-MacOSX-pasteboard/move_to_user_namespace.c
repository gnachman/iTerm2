#import "move_to_user_namespace.h"
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <sys/utsname.h> /* uname  */
#import "iTermFileDescriptorServer.h"

#define FIND_SYMBOL(NAME, RET, SIG) \
    static const char fn_ ## NAME [] = # NAME; \
    typedef RET (*ft_ ## NAME) SIG; \
    ft_ ## NAME f_ ## NAME; \
    if (!(f_ ## NAME = (ft_ ## NAME)dlsym(RTLD_NEXT, fn_ ## NAME))) { \
        iTermFileDescriptorServerLog("unable to find %s: %s", fn_ ## NAME, dlerror()); \
        return -1; \
    }

static unsigned int detect_os_version(void);

static int move_to_user_namespace__100500(void)
{
    FIND_SYMBOL(_vprocmgr_move_subset_to_user, void *, (uid_t, const char *))

    if (f__vprocmgr_move_subset_to_user(getuid(), "Background") != NULL) {
        iTermFileDescriptorServerLog("%s failed", fn__vprocmgr_move_subset_to_user);
        return -1;
    }

    return 0;
}

static int move_to_user_namespace__100600(void)
{
    FIND_SYMBOL(_vprocmgr_move_subset_to_user, void *, (uid_t, const char *, uint64_t))

    if (f__vprocmgr_move_subset_to_user(getuid(), "Background", 0) != NULL) {
        iTermFileDescriptorServerLog("%s failed", fn__vprocmgr_move_subset_to_user);
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
        iTermFileDescriptorServerLog("%s failed", fn_bootstrap_get_root);
        return -1;
    }
    if (f_bootstrap_look_up_per_user(rootbs, NULL, getuid(), &puc) != KERN_SUCCESS) {
        iTermFileDescriptorServerLog("%s failed", fn_bootstrap_look_up_per_user);
        return -1;
    }

    if (task_set_bootstrap_port(mach_task_self(), puc) != KERN_SUCCESS) {
        iTermFileDescriptorServerLog("task_set_bootstrap_port failed");
        return -1;
    }
    if (mach_port_deallocate(mach_task_self(), bootstrap_port) != KERN_SUCCESS) {
        iTermFileDescriptorServerLog("mach_port_deallocate failed");
        return -1;
    }

    bootstrap_port = puc;

    return 0;
}

int move_to_user_namespace(void)
{
    unsigned int os = detect_os_version();
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

static unsigned int detect_os_version(void) {
    unsigned int os = 0;

    struct utsname u;
    if (uname(&u)) {
        iTermFileDescriptorServerLog("uname failed");
        return -1;
    }
    if (strcmp(u.sysname, "Darwin")) {
        iTermFileDescriptorServerLog("unsupported OS sysname: %s", u.sysname);
        return -1;
    }

    char *rest, *whole = strdup(u.release);
    if (!whole) {
        iTermFileDescriptorServerLog("strdup failed");
        return -1;
    }
    rest = whole;
    strsep(&rest, ".");
    if (whole && *whole && whole != rest) {
        int major = atoi(whole);
        os = 100000;    /* 10.1, 10.0 and prior betas/previews */
        if (major >= 6) /* 10.2 and newer */
            os += (major-4) * 100;
    }
    else
        iTermFileDescriptorServerLog("unparsable major release number: '%s'", u.release);

    free(whole);

    /*
     * change the 'os' variable to represent the "reattach variation"
     * instead of the major OS release
     *
     *  older => 100500 with warning
     *   10.5 => 100500
     *   10.6 => 100600
     *   10.7 => 100600
     *   10.8 => 100600
     *   10.9 => 100600
     *   10.10=> 101000
     *   10.11=> 101000
     *   10.12=> 101000
     *   10.13=> 101000
     *  newer => 101000 with warning
     */
    if (100600 <= os && os <= 100900)
        os = 100600;
    else if (101000 <= os && os <= 101300)
        os = 101000;
    else if (os < 100500) {
        iTermFileDescriptorServerLog("unsupported old OS, trying as if it were 10.5");
        os = 100500;
    } else if (os > 101300) {
        iTermFileDescriptorServerLog("unsupported new OS, trying as if it were 10.10");
        os = 101000;
    }

    return os;
}
