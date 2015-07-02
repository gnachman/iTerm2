//
//  EquivalenceClassSet.h
//  iTerm
//
//  Created by George Nachman on 12/28/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EquivalenceClassSet.h"
#import "EquivalenceClassSetTest.h"

@implementation EquivalenceClassSetTest

+ (void)basicTest
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	NSArray *ec = [e valuesEqualTo:n1];
	assert(ec.count == 2);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);

	ec = [e valuesEqualTo:n2];
	assert(ec.count == 2);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);

	ec = [e valuesEqualTo:n3];
	assert(ec.count == 0);
}

+ (void)doubleAdd
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n1 equalToValue:n2];
	NSArray *ec = [e valuesEqualTo:n1];
	assert(ec.count == 2);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);
}

+ (void)mergeClasses
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	NSNumber *n4 = [NSNumber numberWithInt:13];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n3 equalToValue:n4];

	NSArray *ec = [e valuesEqualTo:n1];
	assert(ec.count == 2);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);

	ec = [e valuesEqualTo:n3];
	assert(ec.count == 2);
	assert([ec containsObject:n3]);
	assert([ec containsObject:n4]);

	[e setValue:n1 equalToValue:n3];
	ec = [e valuesEqualTo:n3];
	assert(ec.count == 4);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);
	assert([ec containsObject:n3]);
	assert([ec containsObject:n4]);
}

+ (void)growClass
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n1 equalToValue:n3];
	NSArray *ec = [e valuesEqualTo:n1];
	assert(ec.count == 3);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);
	assert([ec containsObject:n3]);
}

+ (void)growClassReverseArgs
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n3 equalToValue:n1];
	NSArray *ec = [e valuesEqualTo:n1];
	assert(ec.count == 3);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n2]);
	assert([ec containsObject:n3]);
}

+ (void)removeValue
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	NSNumber *n3 = [NSNumber numberWithInt:12];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e setValue:n3 equalToValue:n1];
	[e removeValue:n2];
	NSArray *ec = [e valuesEqualTo:n1];
	assert(ec.count == 2);
	assert([ec containsObject:n1]);
	assert([ec containsObject:n3]);
}

+ (void)removeValueErasingSet
{
	NSNumber *n1 = [NSNumber numberWithInt:10];
	NSNumber *n2 = [NSNumber numberWithInt:11];
	EquivalenceClassSet *e = [[[EquivalenceClassSet alloc] init] autorelease];
	[e setValue:n1 equalToValue:n2];
	[e removeValue:n2];
	NSArray *ec = [e valuesEqualTo:n1];
	assert(!ec);
}

+ (void)runTests
{
	[EquivalenceClassSetTest basicTest];
	[EquivalenceClassSetTest doubleAdd];
	[EquivalenceClassSetTest growClass];
	[EquivalenceClassSetTest growClassReverseArgs];
	[EquivalenceClassSetTest mergeClasses];
	[EquivalenceClassSetTest removeValue];
	[EquivalenceClassSetTest removeValueErasingSet];
}

@end

