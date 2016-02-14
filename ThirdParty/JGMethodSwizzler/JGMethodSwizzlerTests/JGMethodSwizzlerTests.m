//
//  JGMethodSwizzlerTests.m
//  JGMethodSwizzlerTests
//
//  Created by Jonas Gessner on 27.10.13.
//  Copyright (c) 2013 Jonas Gessner. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "JGMethodSwizzler.h"


@interface JGMethodSwizzlerTests : XCTestCase

@end

@implementation JGMethodSwizzlerTests



- (int)a:(int)b {
    return b-2;
}

+ (CGRect)testRect {
    return CGRectMake(0.0f, 1.0f, 2.0f, 3.0f);
}


+ (CGRect)testRect2:(CGRect)r {
    return CGRectInset(r, 10.0f, 10.0f);
}







- (NSObject *)applySwizzles {
    int add = arc4random_uniform(50);
    
    [self.class swizzleInstanceMethod:@selector(a:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int b) {
            int orig = JGOriginalImplementation(int, b);
            return orig+add;
        };
    }];
    
    int yoo = arc4random_uniform(100);
    
    int aa = [self a:yoo];
    
    XCTAssert(aa == yoo-2+add, @"Integer calculation mismatch");
    
    [self.class swizzleClassMethod:@selector(testRect) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(CGRect, const Class *) {
            CGRect orig = JGOriginalImplementation(CGRect);
            
            return CGRectInset(orig, -5.0f, -5.0f);
        };
    }];
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), -5.0f, -5.0f)), @"CGRect swizzling failed");
    
    [self.class swizzleClassMethod:@selector(testRect2:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(CGRect, const Class *, CGRect rect) {
            CGRect orig = JGOriginalImplementation(CGRect, rect);
            
            return CGRectInset(orig, -5.0f, -5.0f);
        };
    }];
    
    
    CGRect testRect = (CGRect){{(CGFloat)arc4random_uniform(100), (CGFloat)arc4random_uniform(100)}, {(CGFloat)arc4random_uniform(100), (CGFloat)arc4random_uniform(100)}};
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:testRect], CGRectInset(CGRectInset(testRect, 10.0f, 10.0f), -5.0f, -5.0f)), @"CGRect swizzling (2) failed");
    
    
    NSObject *object = [NSObject new];
    
    
    [object swizzleMethod:@selector(description) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(NSString *, NSObject *) {
            NSString *orig = JGOriginalImplementation(NSString *);
            
            return [orig stringByAppendingString:@"Only swizzled this instance"];
        };
    }];
    
    XCTAssert([[object description] hasSuffix:@"Only swizzled this instance"] && ![[[NSObject new] description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed");
    
    [object swizzleMethod:@selector(init) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(id, NSObject *) {
            id orig = JGOriginalImplementation(id);
            
            return orig;
        };
    }];
    
    return object;
}

- (void)removeSwizzles1:(NSObject *)object {
    BOOL ok = [object deswizzleMethod:@selector(description)];
    BOOL ok1 = [object deswizzleMethod:@selector(init)];
    BOOL ok2 = [object deswizzle];
    BOOL ok3 = deswizzleInstances();
    
    XCTAssert(ok3 == NO && ok == YES && ok1 == YES && ok2 == NO && ![[object description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed (1)");
    
    
    BOOL ok4 = [self.class deswizzleInstanceMethod:@selector(a:)];
    
    BOOL ok5 = [self.class deswizzleClassMethod:@selector(testRect)];
    BOOL ok6 = [self.class deswizzleClassMethod:@selector(testRect2:)];
    
    
    BOOL ok10 = deswizzleGlobal();
    
    BOOL ok9 = [self.class deswizzleAllMethods];
    
    BOOL ok8 = [self.class deswizzleAllInstanceMethods];
    BOOL ok7 = [self.class deswizzleAllClassMethods];
    
    
    XCTAssert(ok10 == NO && ok9 == NO && ok8 == NO && ok7 == NO && ok4 == YES && ok5 == YES && ok6 == YES && [self a:10] == 8, @"Deswizzling failed");
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)), @"Deswizzling failed (1)");
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), 10.0f, 10.0f)), @"Deswizzling failed (2)");
}

- (void)removeSwizzles2:(NSObject *)object {
    BOOL ok2 = [object deswizzle];
    BOOL ok3 = deswizzleInstances();
    BOOL ok = [object deswizzleMethod:@selector(description)];
    BOOL ok1 = [object deswizzleMethod:@selector(init)];
    
    XCTAssert(ok3 == NO && ok == NO && ok1 == NO && ok2 == YES && ![[object description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed (1)");
    
    
    BOOL ok6 = [self.class deswizzleInstanceMethod:@selector(a:)];
    BOOL ok7 = [self.class deswizzleAllClassMethods];
    
    BOOL ok10 = deswizzleGlobal();
    
    BOOL ok9 = [self.class deswizzleAllMethods];
    
    BOOL ok8 = [self.class deswizzleAllInstanceMethods];
    
    
    BOOL ok4 = [self.class deswizzleClassMethod:@selector(testRect)];
    BOOL ok5 = [self.class deswizzleClassMethod:@selector(testRect2:)];
    
    
    XCTAssert(ok10 == NO && ok8 == NO && ok9 == NO && ok6 == YES && ok7 == YES && ok4 == NO && ok5 == NO && [self a:10] == 8, @"Deswizzling failed");
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)), @"Deswizzling failed (1)");
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), 10.0f, 10.0f)), @"Deswizzling failed (2)");
}



- (void)removeSwizzles3:(NSObject *)object {
    BOOL ok3 = deswizzleInstances();
    BOOL ok2 = [object deswizzle];
    BOOL ok = [object deswizzleMethod:@selector(description)];
    BOOL ok1 = [object deswizzleMethod:@selector(init)];
    
    XCTAssert(ok3 == YES && ok == NO && ok1 == NO && ok2 == NO && ![[object description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed (1)");
    
    
    BOOL ok6 = [self.class deswizzleAllInstanceMethods];
    BOOL ok7 = [self.class deswizzleAllClassMethods];
    
    BOOL ok10 = deswizzleGlobal();
    
    BOOL ok9 = [self.class deswizzleAllMethods];
    
    BOOL ok8 = [self.class deswizzleInstanceMethod:@selector(a:)];
    
    BOOL ok4 = [self.class deswizzleClassMethod:@selector(testRect)];
    BOOL ok5 = [self.class deswizzleClassMethod:@selector(testRect2:)];
    
    
    XCTAssert(ok9 == NO && ok10 == NO && ok6 == YES && ok7 == YES && ok4 == NO && ok5 == NO && ok8 == NO && [self a:10] == 8, @"Deswizzling failed");
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)), @"Deswizzling failed (1)");
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), 10.0f, 10.0f)), @"Deswizzling failed (2)");
}



- (void)removeSwizzles4:(NSObject *)object {
    BOOL ok3 = deswizzleInstances();
    BOOL ok = [object deswizzleMethod:@selector(description)];
    BOOL ok1 = [object deswizzleMethod:@selector(init)];
    BOOL ok2 = [object deswizzle];
    
    XCTAssert(ok3 == YES && ok == NO && ok1 == NO && ok2 == NO && ![[object description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed (1)");
    
    
    BOOL ok9 = [self.class deswizzleAllMethods];
    
    BOOL ok10 = deswizzleGlobal();
    
    BOOL ok6 = [self.class deswizzleAllInstanceMethods];
    BOOL ok7 = [self.class deswizzleAllClassMethods];
    
    BOOL ok8 = [self.class deswizzleInstanceMethod:@selector(a:)];
    
    BOOL ok4 = [self.class deswizzleClassMethod:@selector(testRect)];
    BOOL ok5 = [self.class deswizzleClassMethod:@selector(testRect2:)];
    
    
    XCTAssert(ok10 == NO && ok9 == YES && ok6 == NO && ok7 == NO && ok4 == NO && ok5 == NO && ok8 == NO && [self a:10] == 8, @"Deswizzling failed");
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)), @"Deswizzling failed (1)");
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), 10.0f, 10.0f)), @"Deswizzling failed (2)");
}



- (void)removeSwizzles5:(NSObject *)object {
    BOOL ok3 = deswizzleInstances();
    BOOL ok = [object deswizzleMethod:@selector(description)];
    BOOL ok1 = [object deswizzleMethod:@selector(init)];
    BOOL ok2 = [object deswizzle];
    
    XCTAssert(ok3 == YES && ok == NO && ok1 == NO && ok2 == NO && ![[object description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed (1)");
    
    
    BOOL ok10 = deswizzleGlobal();
    
    BOOL ok9 = [self.class deswizzleAllMethods];
    
    BOOL ok6 = [self.class deswizzleAllInstanceMethods];
    BOOL ok7 = [self.class deswizzleAllClassMethods];
    
    BOOL ok8 = [self.class deswizzleInstanceMethod:@selector(a:)];
    
    BOOL ok4 = [self.class deswizzleClassMethod:@selector(testRect)];
    BOOL ok5 = [self.class deswizzleClassMethod:@selector(testRect2:)];
    
    
    XCTAssert(ok10 == YES && ok9 == NO && ok6 == NO && ok7 == NO && ok4 == NO && ok5 == NO && ok8 == NO && [self a:10] == 8, @"Deswizzling failed");
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)), @"Deswizzling failed (1)");
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), 10.0f, 10.0f)), @"Deswizzling failed (2)");
}



- (void)removeSwizzles6:(NSObject *)object {
    BOOL ok11 = deswizzleAll();
    
    
    BOOL ok3 = deswizzleInstances();
    BOOL ok = [object deswizzleMethod:@selector(description)];
    BOOL ok1 = [object deswizzleMethod:@selector(init)];
    BOOL ok2 = [object deswizzle];
    
    XCTAssert(ok11 == YES && ok3 == NO && ok == NO && ok1 == NO && ok2 == NO && ![[object description] hasSuffix:@"Only swizzled this instance"], @"Instance swizzling failed (1)");
    
    
    BOOL ok10 = deswizzleGlobal();
    
    BOOL ok9 = [self.class deswizzleAllMethods];
    
    BOOL ok6 = [self.class deswizzleAllInstanceMethods];
    BOOL ok7 = [self.class deswizzleAllClassMethods];
    
    BOOL ok8 = [self.class deswizzleInstanceMethod:@selector(a:)];
    
    BOOL ok4 = [self.class deswizzleClassMethod:@selector(testRect)];
    BOOL ok5 = [self.class deswizzleClassMethod:@selector(testRect2:)];
    
    
    XCTAssert(ok10 == NO && ok9 == NO && ok6 == NO && ok7 == NO && ok4 == NO && ok5 == NO && ok8 == NO && [self a:10] == 8, @"Deswizzling failed");
    
    XCTAssert(CGRectEqualToRect([self.class testRect], CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)), @"Deswizzling failed (1)");
    
    
    XCTAssert(CGRectEqualToRect([self.class testRect2:CGRectMake(0.0f, 1.0f, 2.0f, 3.0f)], CGRectInset(CGRectMake(0.0f, 1.0f, 2.0f, 3.0f), 10.0f, 10.0f)), @"Deswizzling failed (2)");
}

//For debugging purposes: (function needs to be uncommented in JGMethodSwizzler.m in order to work)
//FOUNDATION_EXTERN NSString *getStatus();



- (void)logStatusBefore {
//    NSLog(@"STATUS BEFORE %@", getStatus());
}

- (void)logStatusAfter {
//    NSLog(@"STATUS AFTER %@", getStatus());
}

- (void)logStatusFinal {
//    NSLog(@"STATUS FINAL %@", getStatus());
}


- (void)testMain {
    [self logStatusBefore];
    NSObject *object = [self applySwizzles];
    [self logStatusAfter];
    [self removeSwizzles1:object];
    
    [self logStatusBefore];
    object = [self applySwizzles];
    [self logStatusAfter];
    [self removeSwizzles2:object];
    
    
    [self logStatusBefore];
    object = [self applySwizzles];
    [self logStatusAfter];
    [self removeSwizzles3:object];
    
    [self logStatusBefore];
    object = [self applySwizzles];
    [self logStatusAfter];
    [self removeSwizzles4:object];
    
    
    [self logStatusBefore];
    object = [self applySwizzles];
    [self logStatusAfter];
    [self removeSwizzles5:object];
    
    
    [self logStatusBefore];
    object = [self applySwizzles];
    [self logStatusAfter];
    [self removeSwizzles6:object];
    
    
    
    [self logStatusFinal];
}


- (int)test:(int)a {
    NSLog(@"ORIGINAL");
    return a+1;
}

- (void)testGlobalAndInstanceSwizzlingCombination1 {
    [self.class swizzleInstanceMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"GLOBAL SWIZZLE");
            return orig+1;
        };
    }];
    
    [self swizzleMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"ISTANCE SWIZZLE");
            return orig+1;
        };
    }];
    
    XCTAssert([self test:1] == 4, @"Integer mismatch");
    
    BOOL ok = [self deswizzleMethod:@selector(test:)];
    
    XCTAssert([self test:1] == 3, @"Integer mismatch");
    
    BOOL ok1 = [self.class deswizzleInstanceMethod:@selector(test:)];
    
    XCTAssert([self test:1] == 2, @"Integer mismatch");
    
    XCTAssert(ok == YES && ok1 == YES, @"Deswizzling failed");
}


- (void)testGlobalAndInstanceSwizzlingCombination2 {
    NSLog(@"Example for why global and instance swizzling is not a good combination");
    [self swizzleMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"ISTANCE SWIZZLE");
            return orig+1;
        };
    }];
    
    //This swizzle would get put between the instance swizzle and the original method implementation. The instance specific swizzle however would not know that this happened and this swizzle would never be invoked on this specific instance. Therefore it throws an exception.
    XCTAssertThrows([self.class swizzleInstanceMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"GLOBAL SWIZZLE");
            return orig+1;
        };
    }], @"Instance and global swizzle failure");
    
    XCTAssert([self test:1] == 3, @"Integer mismatch");
    
    BOOL ok = [self.class deswizzleInstanceMethod:@selector(test:)];
    
    XCTAssert([self test:1] == 3, @"Integer mismatch");
    
    BOOL ok1 = [self deswizzleMethod:@selector(test:)];
    
    XCTAssert([self test:1] == 2, @"Integer mismatch");
    
    XCTAssert(ok == NO && ok1 == YES, @"Deswizzling failed");
}


- (void)testGlobalAndInstanceSwizzlingCombination3 {
    NSLog(@"Example for why global and instance swizzling is not a good combination");
    [self swizzleMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"ISTANCE SWIZZLE");
            return orig+1;
        };
    }];
    
    //This swizzle would get put between the instance swizzle and the original method implementation. The instance specific swizzle however would not know that this happened and this swizzle would never be invoked on this specific instance. Therefore it throws an exception.
    XCTAssertThrows([self.class swizzleInstanceMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"GLOBAL SWIZZLE");
            return orig+1;
        };
    }], @"Instance and global swizzle failure");
    
    XCTAssert([self test:1] == 3, @"Integer mismatch");
    
    BOOL ok = [self deswizzleMethod:@selector(test:)];
    
    XCTAssert([self test:1] == 2, @"Integer mismatch");
    
    BOOL ok1 = [self.class deswizzleInstanceMethod:@selector(test:)];
    
    XCTAssert([self test:1] == 2, @"Integer mismatch");
    
    
    XCTAssert(ok == YES && ok1 == NO, @"Deswizzling Failed");
}


- (void)testGlobalAndInstanceSwizzlingCombination4 {
    [self.class swizzleInstanceMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"GLOBAL SWIZZLE");
            return orig+1;
        };
    }];
    
    [self swizzleMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(int, JGMethodSwizzlerTests *, int a) {
            int orig = JGOriginalImplementation(int, a);
            NSLog(@"ISTANCE SWIZZLE");
            return orig+1;
        };
    }];
    
    XCTAssert([self test:1] == 4, @"Integer mismatch");
    
    BOOL ok3 = [self deswizzle];
    
    XCTAssert([self test:1] == 3, @"Integer mismatch");
    
    BOOL ok4 = [self.class deswizzleAllMethods];
    
    XCTAssert([self test:1] == 2, @"Integer mismatch");
    
    BOOL ok = [self deswizzleMethod:@selector(test:)];
    
    BOOL ok1 = [self.class deswizzleInstanceMethod:@selector(test:)];
    
    XCTAssert(ok3 == YES && ok4 == YES && ok == NO && ok1 == NO, @"Deswizzling failed");
}


@end

