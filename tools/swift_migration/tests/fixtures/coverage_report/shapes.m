// Fixture for tools/swift_migration/tests/test_coverage_report.py. The tests
// find lines by the "M:" markers in comments, so keep each marker on the line
// it describes. main() at the bottom says which paths run.

#import <Foundation/Foundation.h>

@interface Shape : NSObject
+ (int)kindFor:(int)x;
- (int)area:(int)w height:(int)h;
@end

@implementation Shape

+ (int)kindFor:(int)x {
    return x > 0 ? 1 : 2;  // M:ternary
}

- (int)area:(int)w height:(int)h {  // M:area-start
    int (^mul)(int, int) = ^int(int a, int b) {
        if (a == 0) {  // M:block-if
            return 0;  // M:block-zero
        }
        return a * b;
    };
    return mul(w, h);
}  // M:area-end

- (int)extra:(int)x {
    return x;
}

@end

@interface Shape (Extra)
- (int)extra:(int)x;
- (int)catOnly;
- (int)clamp:(int)x;
@end

@implementation Shape (Extra)

- (int)extra:(int)x {
    while (x > 0) {  // M:cat-while
        x--;
    }
    return x;
}

- (int)catOnly {  // M:cat-only
    return 7;
}

- (int)clamp:(int)x {
    return MAX(x, 1);  // M:sdk-max
}

@end

int main(void) {
    @autoreleasepool {
        Shape *s = [Shape new];
        printf("%d %d %d\n", [Shape kindFor:1], [s area:2 height:3], [s extra:0] + [s catOnly] + [s clamp:5]);
    }
    return 0;
}
