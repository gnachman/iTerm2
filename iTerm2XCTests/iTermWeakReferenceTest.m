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

@interface iTermWeaklyReferenceableObject : NSObject<iTermWeaklyReferenceable>
@end

@implementation iTermWeaklyReferenceableObject

ITERM_WEAKLY_REFERENCEABLE

@end

@interface iTerm2FakeObject : NSObject<iTermWeaklyReferenceable>
@property(nonatomic, assign) int number;
@end

@implementation iTerm2FakeObject
ITERM_WEAKLY_REFERENCEABLE
@end

@interface iTermWeakReferenceTest : XCTestCase

@end

@interface WRTObject : NSObject<iTermWeaklyReferenceable>
@property(nonatomic, assign) iTermWeakReference *reference;
@property(nonatomic, assign) BOOL *okPointer;
@end

@implementation WRTObject

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    *_okPointer = (_reference && _reference.internal_unsafeObject == nil);
    [super dealloc];
}

@end

@implementation iTermWeakReferenceTest

- (void)testSimpleCase {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    XCTAssert(object.retainCount == 1);
    iTermWeaklyReferenceableObject *weakReference = [object weakSelf];
    XCTAssert(object.retainCount == 1);
    XCTAssert([(id)weakReference internal_unsafeObject] == object);
    [object release];
    XCTAssert([(id)weakReference internal_unsafeObject] == nil);
}

- (void)testWeaklyReferencedObjectMethodBeforeDealloc {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    iTermWeaklyReferenceableObject<iTermWeakReference> *weakReference = [object weakSelf];
    XCTAssertEqual(weakReference.weaklyReferencedObject, object);
    [object release];
}

- (void)testWeaklyReferencedObjectMethodAfterDealloc {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    iTermWeaklyReferenceableObject<iTermWeakReference> *weakReference = [object weakSelf];
    [object release];
    XCTAssertEqual(weakReference.weaklyReferencedObject, nil);
}

- (void)testTwoWeakRefsToSameObject {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    XCTAssert(object.retainCount == 1);
    iTermWeaklyReferenceableObject *weakReference1 = [object weakSelf];
    XCTAssert(object.retainCount == 1);
    iTermWeaklyReferenceableObject *weakReference2 = [object weakSelf];
    XCTAssert(object.retainCount == 1);

    XCTAssert([(id)weakReference1 internal_unsafeObject] == object);
    XCTAssert([(id)weakReference2 internal_unsafeObject] == object);
    XCTAssert(object.retainCount == 1);

    [object release];
    XCTAssert([(id)weakReference1 internal_unsafeObject] == nil);
    XCTAssert([(id)weakReference2 internal_unsafeObject] == nil);
}

- (void)testReleaseWeakReferenceBeforeObject {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
    iTermWeakReference *weakReference = [[iTermWeakReference alloc] initWithObject:object];
    [weakReference release];
    XCTAssert(object.retainCount == 1);
    [object release];
}

- (void)testReleaseTwoWeakReferencesBeforeObject {
    iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
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

- (void)testProxyForwardsExistingMethods {
    iTerm2FakeObject *fakeObject = [[[iTerm2FakeObject alloc] init] autorelease];
    fakeObject.number = 1234;
    iTerm2FakeObject *ref = [fakeObject weakSelf];
    XCTAssertEqual([ref number], 1234);
}

- (void)testProxyRaisesExceptionOnNonexistantMethods {
    iTerm2FakeObject *fakeObject = [[[iTerm2FakeObject alloc] init] autorelease];
    NSString *ref = [fakeObject weakSelf];
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
        iTermWeaklyReferenceableObject *object = [[iTermWeaklyReferenceableObject alloc] init];
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
