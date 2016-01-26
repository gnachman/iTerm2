//
//  OCMockito - MKTOngoingStubbing.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import <Foundation/Foundation.h>
#import "MKTPrimitiveArgumentMatching.h"

@class MKTInvocationContainer;


/**
    Methods to invoke on @c given(methodCall) to return stubbed values.
 */
@interface MKTOngoingStubbing : NSObject <MKTPrimitiveArgumentMatching>

- (id)initWithInvocationContainer:(MKTInvocationContainer *)invocationContainer;

/// Stubs given object as return value.
- (MKTOngoingStubbing *)willReturn:(id)object;

/// Stubs given @c BOOL as return value.
- (MKTOngoingStubbing *)willReturnBool:(BOOL)value;

/// Stubs given @c char as return value.
- (MKTOngoingStubbing *)willReturnChar:(char)value;

/// Stubs given @c int as return value.
- (MKTOngoingStubbing *)willReturnInt:(int)value;

/// Stubs given @c short as return value.
- (MKTOngoingStubbing *)willReturnShort:(short)value;

/// Stubs given @c long as return value.
- (MKTOngoingStubbing *)willReturnLong:(long)value;

/// Stubs given <code>long long</code> as return value.
- (MKTOngoingStubbing *)willReturnLongLong:(long long)value;

/// Stubs given @c NSInteger as return value.
- (MKTOngoingStubbing *)willReturnInteger:(NSInteger)value;

/// Stubs given <code>unsigned char</code> as return value.
- (MKTOngoingStubbing *)willReturnUnsignedChar:(unsigned char)value;

/// Stubs given <code>unsigned int</code> as return value.
- (MKTOngoingStubbing *)willReturnUnsignedInt:(unsigned int)value;

/// Stubs given <code>unsigned short</code> as return value.
- (MKTOngoingStubbing *)willReturnUnsignedShort:(unsigned short)value;

/// Stubs given <code>unsigned long</code> as return value.
- (MKTOngoingStubbing *)willReturnUnsignedLong:(unsigned long)value;

/// Stubs given <code>unsigned long long</code> as return value.
- (MKTOngoingStubbing *)willReturnUnsignedLongLong:(unsigned long long)value;

/// Stubs given @c NSUInteger as return value.
- (MKTOngoingStubbing *)willReturnUnsignedInteger:(NSUInteger)value;

/// Stubs given @c float as return value.
- (MKTOngoingStubbing *)willReturnFloat:(float)value;

/// Stubs given @c double as return value.
- (MKTOngoingStubbing *)willReturnDouble:(double)value;

@end
