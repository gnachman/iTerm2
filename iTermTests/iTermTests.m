//
//  iTermTests.m
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import "iTermTests.h"
#import <objc/runtime.h>

@implementation iTermTest @end

#define DECLARE_TEST(t) @interface t : iTermTest @end
#define PERFORM_IF_RESPONDS(SELECT,...) ![test respondsToSelector:@selector(SELECT)] ?: [test SELECT]; NSLog(__VA_ARGS__)
#define RUN_TEST_CLASSES(...) ({ for (Class x in @[__VA_ARGS__]) RunTestsInObject([[x new] autorelease]); })

DECLARE_TEST(VT100GridTest)
DECLARE_TEST(VT100ScreenTest)
DECLARE_TEST(IntervalTreeTest)
DECLARE_TEST(AppleScriptTest)
DECLARE_TEST(NSStringCategoryTest)

static void RunTestsInObject(iTermTest *test) {

    NSLog(@"-- Begin tests in %@ --", test.class);
    unsigned int methodCount;
    Method *methods = class_copyMethodList(test.class, &methodCount);
    for (int i = 0; i < methodCount; i++) { NSString *stringName; SEL selector;
      selector   = method_getName(methods[i]);
      stringName = NSStringFromSelector(selector);
        if (![stringName hasPrefix:@"test"]) continue;
        PERFORM_IF_RESPONDS(setup, @"Running %@", stringName);
        [test performSelector:selector];
        PERFORM_IF_RESPONDS(teardown, @"Success!");
    }
    free(methods);
    NSLog(@"-- Finished tests in %@ --", [test class]);
}

int main(int argc, const char * argv[]) { return

  RUN_TEST_CLASSES(   VT100GridTest.class,
                    VT100ScreenTest.class,
                   IntervalTreeTest.class,
               NSStringCategoryTest.class,
                    AppleScriptTest.class),

                    NSLog(@"All tests passed"), 0;
}
