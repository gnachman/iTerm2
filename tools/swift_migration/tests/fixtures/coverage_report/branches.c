// Fixture for tools/swift_migration/tests/test_coverage_report.py. The tests
// find lines by the "M:" markers in comments, so keep each marker on the line
// it describes. main() at the bottom says which paths run; with any argument it also
// calls never_called().

#include <stdio.h>

#define IS_POSITIVE(x) ((x) > 0 ? 1 : 0)  // M:macro-cond

// A logging macro shaped like DLog: its branch is never taken in a run with
// logging off. LOUD nests it, as ELog nests DLog.
static int gLog;
#define LOGF(x) do { if (gLog) { printf("%d\n", x); } } while (0)
#define LOUD(x) do { LOGF(x); } while (0)

int if_else(int x) {
    if (x > 0) {  // M:if
        return 1;
    } else {
        return -1;  // M:else-body
    }
}

int sw(int x) {
    switch (x) {
        case 1:  // M:case1
            return 10;
        case 2:  // M:case2
            return 20;  // M:case2-body
        default:  // M:default
            return 0;
    }
}

int sw_no_default(int x) {
    switch (x) {  // M:switch-nd
        case 1:  // M:nd-case1
            return 1;
        case 3:  // M:nd-case3
            return 3;
    }
    return 0;
}

int short_circuit(int a, int b) {
    if (a && b) {  // M:and
        return 1;  // M:and-body
    }
    return 0;
}

int never_iterates(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {  // M:for
        s += i;  // M:for-body
    }
    return s;
}

int forever(int x) {
    while (1) {  // M:while1
        if (x > 3) {  // M:while-if
            break;
        }
        x++;
    }
    return x || 0;  // M:or-folded
}

int never_called(int x) {  // M:never-start
    if (x) {  // M:never-if
        return 2;
    }
    return 3;
}

int macro_branch(int x) {
    return IS_POSITIVE(x);  // M:macro-use
}

int full(int x) {  // M:full
    if (x) {
        return 1;
    }
    return 0;
}

int logged(int x) {
    LOGF(x);  // M:logf
    LOUD(x);  // M:loud
    return x;
}

int main(int argc, char **argv) {
    (void)argv;
    int t = if_else(1);
    t += sw(1) + sw(7);
    t += sw_no_default(1) + sw_no_default(3);
    t += short_circuit(0, 1);
    t += never_iterates(0);
    t += forever(0);
    t += macro_branch(5);
    t += full(0) + full(1);
    t += logged(1);
    if (argc > 1) {
        t += never_called(argc);  // M:main-never
    }
    printf("%d\n", t);
    return 0;
}
