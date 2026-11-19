// Fixture for tools/swift_migration/tests/test_coverage_report.py: blocks
// that never ran, with and without branches, nested blocks, a block given
// to a function that never calls it, and @try/@catch, whose @catch body
// clang does not count separately. The tests find lines by the "M:"
// markers in comments. main() says which paths run.

#import <Foundation/Foundation.h>

static void neverCalls(void (^block)(void)) {
    (void)block;
}

int b_never_plain(int x) {
    int (^never)(int) = ^(int y) { return y + 1; };  // M:bnp
    (void)never;
    if (x) {
        return 1;
    }
    return 0;
}

int b_never_branch(int x) {
    int (^never)(int) = ^(int y) {  // M:bnb
        if (y) {  // M:bnb-if
            return 1;
        }
        return 0;
    };
    (void)never;
    return x;
}

int b_invoked(int x) {
    int (^once)(int) = ^(int y) { return y * 2; };  // M:bi
    return once(x);
}

int b_nested(int x) {
    int (^outer)(int) = ^(int y) {  // M:bn-outer
        int (^inner)(int) = ^(int z) { return z + 1; };  // M:bn-inner
        (void)inner;
        return y;
    };
    return outer(x);
}

int b_passed(int x) {
    neverCalls(^{ printf("never\n"); });  // M:bp
    return x;
}

static void thrower(int x) {
    if (x) {
        @throw [NSException exceptionWithName:@"n" reason:@"r" userInfo:nil];
    }
}

int t_try(int x, int y) {
    int r = 0;
    @try {
        thrower(x);
        r = 1;
    } @catch (NSException *e) {  // M:catch
        if (y > 5) {  // M:catch-if
            r = 2;
        }
    } @finally {
        r += 10;
    }
    return r;
}

int t_try_plain(int x) {
    int r = 0;
    @try {
        thrower(x);
        r = 1;
    } @catch (NSException *e) {  // M:catch-plain
        r = 2;
    }
    return r;
}

int t_full(int x) {
    if (x) {
        return 1;
    }
    return 0;
}

int t_try_ifdef(int x) {
    int r = 0;
    @try {
        thrower(x);
        r = 1;
#if 0
        }
#endif
    } @catch (NSException *e) {  // M:catch-ifdef
        if (x > 0) {  // M:catch-ifdef-if
            r = 2;
        }
    }
    return r;
}

int t_finally_only(int x) {
    int r = 0;
    @try {
        if (x > 3) r = 5;  // M:finally-if
        r += 1;
    } @finally {
        r += 10;
    }
    return r;
}

int main(void) {
    @autoreleasepool {
        int t = b_never_plain(0) + b_never_plain(1);
        t += b_never_branch(1);
        t += b_invoked(2);
        t += b_nested(3);
        t += b_passed(4);
        t += t_try(0, 1);
        t += t_try_plain(0);
        t += t_full(0) + t_full(1);
        t += t_try_ifdef(0) + t_try_ifdef(1);
        t += t_finally_only(1);
        printf("%d\n", t);
    }
    return 0;
}
