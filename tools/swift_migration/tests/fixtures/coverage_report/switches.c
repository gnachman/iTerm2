// Fixture for tools/swift_migration/tests/test_coverage_report.py: the
// implicit default of a switch with no default label, told apart from the
// branches of ?:, && and || in the switch's condition. The tests find lines
// by the "M:" markers in comments. main() says which paths run.

int nd_plain(int x) {
    switch (x) {  // M:nd-plain
        case 1: return 10;
    }
    return 0;
}

int nd_tern(int x, int y) {
    switch (y ? x : 0) {  // M:nd-tern
        case 1: return 10;
    }
    return 0;
}

int nd_and(int a, int b) {
    switch (a && b) {  // M:nd-and
        case 1: return 10;
    }
    return 0;
}

int nd_or(int a, int b) {
    switch (a || b) {  // M:nd-or
        case 1: return 10;
    }
    return 0;
}

int nd_multiline(int x) {
    switch (  // M:nd-ml-switch
        x) {  // M:nd-ml-cond
        case 1: return 10;
    }
    return 0;
}

int nd_multiline_tern(int x, int y) {
    switch (  // M:nd-mlt-switch
        y ? x : 0) {  // M:nd-mlt-cond
        case 1: return 10;
    }
    return 0;
}

int d_plain(int x) {
    switch (x) {  // M:d-plain
        case 1: return 10;
        default: return 0;
    }
}

int d_tern(int x, int y) {
    switch (y ? x : 0) {  // M:d-tern
        case 1: return 10;
        default: return 0;
    }
}

int d_and(int a, int b) {
    switch (a && b) {  // M:d-and
        case 1: return 10;
        default: return 0;
    }
}

int d_or(int a, int b) {
    switch (a || b) {  // M:d-or
        case 1: return 10;
        default: return 0;
    }
}

int d_multiline_tern(int x, int y) {
    switch (
        y ? x : 0) {  // M:d-mlt-cond
        case 1: return 10;
        default: return 0;
    }
}

int main(void) {
    int t = nd_plain(1) + nd_plain(2);
    t += nd_tern(1, 1);
    t += nd_and(1, 1) + nd_and(0, 1);
    t += nd_or(0, 0);
    t += nd_multiline(1);
    t += nd_multiline_tern(1, 1) + nd_multiline_tern(5, 1);
    t += d_plain(1);
    t += d_tern(5, 0) + d_tern(0, 0);
    t += d_and(0, 1);
    t += d_or(1, 0);
    t += d_multiline_tern(1, 1);
    return t > 1000;
}
