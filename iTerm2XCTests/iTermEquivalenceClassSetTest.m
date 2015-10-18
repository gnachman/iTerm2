//
//  EquivalenceClassSet.h
//  iTerm
//
//  Created by George Nachman on 12/28/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "EquivalenceClassSet.h"

@interface iTermEquivalenceClassSetTest : XCTestCase
@end


@implementation iTermEquivalenceClassSetTest

- (void)testBasic {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(ec.count == 2);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);

	ec = [e valuesEqualTo:n2];
	XCTAssert(ec.count == 2);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);

	ec = [e valuesEqualTo:n3];
	XCTAssert(ec.count == 0);
}

- (void)testAddDouble {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n1 equalToValue:n2];
	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(ec.count == 2);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);
}

- (void)testMergeClasses {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	NSNumber *n4 = [NSNumber numberWithInt:13];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n3 equalToValue:n4];

	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(ec.count == 2);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);

	ec = [e valuesEqualTo:n3];
	XCTAssert(ec.count == 2);
	XCTAssert([ec containsObject:n3]);
	XCTAssert([ec containsObject:n4]);

	[e setValue:n1 equalToValue:n3];
	ec = [e valuesEqualTo:n3];
	XCTAssert(ec.count == 4);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);
	XCTAssert([ec containsObject:n3]);
	XCTAssert([ec containsObject:n4]);
}

- (void)testGrowClass {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n1 equalToValue:n3];
	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(ec.count == 3);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);
	XCTAssert([ec containsObject:n3]);
}

- (void)testGrowClassReverseArgs {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n3 equalToValue:n1];
	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(ec.count == 3);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n2]);
	XCTAssert([ec containsObject:n3]);
}

- (void)testRemoveValue {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n3 equalToValue:n1];
	[e removeValue:n2];
	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(ec.count == 2);
	XCTAssert([ec containsObject:n1]);
	XCTAssert([ec containsObject:n3]);
}

- (void)testRemoveValueErasingSet {
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e removeValue:n2];
	NSSet *ec = [e valuesEqualTo:n1];
	XCTAssert(!ec);
}

@end

