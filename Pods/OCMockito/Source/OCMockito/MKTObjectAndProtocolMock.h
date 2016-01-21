//
//  OCMockito - MKTObjectAndProtocolMock.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Kevin Lundberg
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTProtocolMock.h"


/**
    Mock object of a given class that also implements a given protocol.
 */
@interface MKTObjectAndProtocolMock : MKTProtocolMock

+ (id)mockForClass:(Class)aClass protocol:(Protocol *)protocol;
- (id)initWithClass:(Class)aClass protocol:(Protocol *)protocol;

@end
