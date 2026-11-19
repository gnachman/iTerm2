// Fixture for tools/swift_migration/tests/test_coverage_report.py: compiled
// into two programs, once with -DVARIANT, which gives tw() a different shape
// and so a separate profile record. The tests find lines by the "M:" markers.

#include <stdio.h>

int tw(int x) {
    if (x > 0) {  // M:tw-if
        return 1;
    }
#ifdef VARIANT
    if (x < -5) {
        return 3;
    }
#endif
    return 2;
}

int main(int argc, char **argv) {
    (void)argv;
#ifdef VARIANT
    printf("%d\n", tw(-argc));
#else
    printf("%d\n", tw(argc));
#endif
    return 0;
}
