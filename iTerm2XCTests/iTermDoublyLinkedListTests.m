//
//  iTermDoublyLinkedListTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 11/5/19.
//

#import <XCTest/XCTest.h>
#import "iTermDoublyLinkedList.h"

@interface iTermDoublyLinkedListTests : XCTestCase

@end

@implementation iTermDoublyLinkedListTests

- (void)testPrepend {
    iTermDoublyLinkedList<NSNumber *> *dll = [[iTermDoublyLinkedList alloc] init];
    iTermDoublyLinkedListEntry<NSNumber *> *e1 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@1];
    iTermDoublyLinkedListEntry<NSNumber *> *e2 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@2];
    [dll prepend:e2];
    [dll prepend:e1];

    XCTAssertNil(dll.first.dllPrevious);
    XCTAssertEqual(@1, dll.first.object);
    XCTAssertEqual(@2, dll.first.dllNext.object);
    XCTAssertNil(dll.first.dllNext.dllNext);

    XCTAssertNil(dll.last.dllNext);
    XCTAssertEqual(@2, dll.last.object);
    XCTAssertEqual(@1, dll.last.dllPrevious.object);
    XCTAssertNil(dll.last.dllPrevious.dllPrevious);
}

- (void)testRemoveFromTail {
    iTermDoublyLinkedList<NSNumber *> *dll = [[iTermDoublyLinkedList alloc] init];
    iTermDoublyLinkedListEntry<NSNumber *> *e1 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@1];
    iTermDoublyLinkedListEntry<NSNumber *> *e2 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@2];
    [dll prepend:e2];
    [dll prepend:e1];

    [dll remove:e2];
    XCTAssertEqual(@1, dll.first.object);
    XCTAssertNil(dll.first.dllNext);
    XCTAssertNil(dll.first.dllPrevious);

    XCTAssertEqual(@1, dll.last.object);
    XCTAssertNil(dll.last.dllPrevious);
    XCTAssertNil(dll.last.dllNext);

    [dll remove:e1];
    XCTAssertNil(dll.first);
    XCTAssertNil(dll.last);
}

- (void)testRemoveFromHead {
    iTermDoublyLinkedList<NSNumber *> *dll = [[iTermDoublyLinkedList alloc] init];
    iTermDoublyLinkedListEntry<NSNumber *> *e1 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@1];
    iTermDoublyLinkedListEntry<NSNumber *> *e2 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@2];
    [dll prepend:e2];
    [dll prepend:e1];

    [dll remove:e1];
    XCTAssertEqual(@2, dll.first.object);
    XCTAssertNil(dll.first.dllNext);
    XCTAssertNil(dll.first.dllPrevious);

    XCTAssertEqual(@2, dll.last.object);
    XCTAssertNil(dll.last.dllPrevious);
    XCTAssertNil(dll.last.dllNext);

    [dll remove:e2];
    XCTAssertNil(dll.first);
    XCTAssertNil(dll.last);
}

- (void)testRemoveMiddle {
    iTermDoublyLinkedList<NSNumber *> *dll = [[iTermDoublyLinkedList alloc] init];
    iTermDoublyLinkedListEntry<NSNumber *> *e1 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@1];
    iTermDoublyLinkedListEntry<NSNumber *> *e2 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@2];
    iTermDoublyLinkedListEntry<NSNumber *> *e3 = [[iTermDoublyLinkedListEntry alloc] initWithObject:@3];
    [dll prepend:e3];
    [dll prepend:e2];
    [dll prepend:e1];

    [dll remove:e2];
    XCTAssertEqual(@1, dll.first.object);
    XCTAssertEqual(@3, dll.first.dllNext.object);
    XCTAssertNil(dll.first.dllNext.dllNext);
    XCTAssertNil(dll.first.dllPrevious);

    XCTAssertEqual(@3, dll.last.object);
    XCTAssertEqual(@1, dll.last.dllPrevious.object);
    XCTAssertNil(dll.last.dllPrevious.dllPrevious);
    XCTAssertNil(dll.last.dllNext);
}

@end
