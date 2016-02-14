//
//  iTermWeakReferenceTest.m
//  iTerm2
//
//  Created by George Nachman on 2/12/16.
//
//

#import <XCTest/XCTest.h>
#import "iTermWeakReference.h"
#import <objc/runtime.h>

@interface iTerm2FakeObject : NSObject
@property(nonatomic, assign) int number;
@end

@implementation iTerm2FakeObject
@end

@interface iTermWeakReferenceTest : XCTestCase

@end

@interface WRTObject : NSObject
@property(nonatomic, assign) iTermWeakReference *reference;
@property(nonatomic, assign) BOOL *okPointer;
@end

@implementation WRTObject

- (void)dealloc {
    *_okPointer = (_reference && _reference.internal_unsafeObject == nil);
    [super dealloc];
}

@end

@interface WTFObject : NSObject
@end

@implementation WTFObject

- (id)retain {
    return [super retain];
}

@end

@implementation iTermWeakReferenceTest

- (void)testSimpleCase {
    NSObject *object = [[NSObject alloc] init];
    XCTAssert(object.retainCount == 1);
    id weakReference = [object weakSelf];
    XCTAssert(object.retainCount == 1);
    XCTAssert([weakReference internal_unsafeObject] == object);
    [object release];
    XCTAssert([weakReference internal_unsafeObject] == nil);
}

- (void)testTwoWeakRefsToSameObject {
    NSObject *object = [[NSObject alloc] init];
    XCTAssert(object.retainCount == 1);
    id weakReference1 = [object weakSelf];
    XCTAssert(object.retainCount == 1);
    id weakReference2 = [object weakSelf];
    XCTAssert(object.retainCount == 1);

    XCTAssert([weakReference1 internal_unsafeObject] == object);
    XCTAssert([weakReference2 internal_unsafeObject] == object);
    XCTAssert(object.retainCount == 1);

    [object release];
    XCTAssert([weakReference1 internal_unsafeObject] == nil);
    XCTAssert([weakReference2 internal_unsafeObject] == nil);
}

- (void)testReleaseWeakReferenceBeforeObject {
    NSObject *object = [[NSObject alloc] init];
    iTermWeakReference *weakReference = [[iTermWeakReference alloc] initWithObject:object];
    [weakReference release];
    XCTAssert(object.retainCount == 1);
    [object release];
}

- (void)testReleaseTwoWeakReferencesBeforeObject {
    NSObject *object = [[NSObject alloc] init];
    iTermWeakReference *weakReference1 = [[iTermWeakReference alloc] initWithObject:object];
    iTermWeakReference *weakReference2 = [[iTermWeakReference alloc] initWithObject:object];
    [weakReference1 release];
    [weakReference2 release];
    XCTAssert(object.retainCount == 1);
    [object release];
}

- (void)testNullfiedAtStartOfDealloc {
    WRTObject *object = [[WRTObject alloc] init];
    BOOL ok = NO;
    object.okPointer = &ok;
    WRTObject *ref = [object weakSelf];
    object.reference = (iTermWeakReference *)ref;
    [object release];
    XCTAssert(((iTermWeakReference *)ref).internal_unsafeObject == nil, @"Reference's object not nullified");
    XCTAssert(ok, @"Reference's object nullified after start of object's dealloc");
}

// The JGMethodSwizzler library has a bug where if you swizzle the a method twice on an instance
// then all instances get swizzled. Make sure we don't have that issue.
- (void)testNotAllObjectsDeallocsSwizzled {
    WRTObject *object1 = [[WRTObject alloc] init];
    WRTObject *object2 = [[WRTObject alloc] init];
    
    WRTObject *ref = [object1 weakSelf];
    BOOL ok1 = NO;
    BOOL ok2 = YES;
    object1.okPointer = &ok1;
    object1.reference = (iTermWeakReference *)ref;
    
    object2.okPointer = &ok2;
    
    [object1 release];
    XCTAssert(ok1, @"First object's dealloc not run");
    XCTAssert(ok2, @"Second object's dealloc did run");
}

- (void)testProxyForwardsExistingMethods {
    NSString *string = @"Hello world";
    NSUInteger length = string.length;
    NSString *ref = [string weakSelf];
    XCTAssertEqual([ref length], length);
}

- (void)testProxyRaisesExceptionOnNonexistantMethods {
    NSString *string = @"Hello world";
    NSString *ref = [string weakSelf];
    BOOL ok = NO;
    @try {
        [ref performSelector:@selector(testProxyRaisesExceptionOnNonexistantMethods)
                  withObject:nil];
    }
    @catch (NSException *e) {
        ok = YES;
    }
    XCTAssertTrue(ok);
}

- (void)testProxyReturnsZeroForFreedObject {
    iTerm2FakeObject *fakeObject = [[iTerm2FakeObject alloc] init];
    fakeObject.number = 1234;
    iTerm2FakeObject *ref = [fakeObject weakSelf];
    [fakeObject release];
    int number = [ref number];
    XCTAssertEqual(number, 0);
}

// This is a nondeterministic test that tries to trigger crashy race conditions. If it passes,
// you learn nothing, but if it crashes you have a bug :). It has caught a few problems so I'll
// keep it around with a low number of iterations.
- (void)testRaceConditions {
    dispatch_queue_t q1 = dispatch_queue_create("com.iterm2.WeakReferenceTest1", NULL);
    dispatch_queue_t q2 = dispatch_queue_create("com.iterm2.WeakReferenceTest2", NULL);
    dispatch_group_t startGroup = dispatch_group_create();
    dispatch_group_t raceGroup = dispatch_group_create();
    dispatch_group_t doneGroup = dispatch_group_create();
    
    for (int i = 0; i < 1000; i++) {
        NSObject *object = [[WTFObject alloc] init];
        iTermWeakReference *ref = [[iTermWeakReference alloc] initWithObject:object];

        dispatch_group_enter(startGroup);
        
        NSValue *objectValue = [NSValue valueWithNonretainedObject:object];
        dispatch_group_async(doneGroup, q1, ^{
            dispatch_group_wait(startGroup, DISPATCH_TIME_FOREVER);
            [objectValue.nonretainedObjectValue release];
        });

        NSValue *refValue = [NSValue valueWithNonretainedObject:ref];
        dispatch_group_async(doneGroup, q2, ^{
            dispatch_group_wait(startGroup, DISPATCH_TIME_FOREVER);
            [refValue.nonretainedObjectValue release];
        });

        // Give everyone time to wait...
        usleep(1000);
        
        // Fire the startign pistol
        dispatch_group_leave(startGroup);
        
        // Wait for the blocks to finish running.
        dispatch_group_wait(doneGroup, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_release(q1);
    dispatch_release(q2);
    dispatch_release(startGroup);
    dispatch_release(raceGroup);
    dispatch_release(doneGroup);
}

@end
