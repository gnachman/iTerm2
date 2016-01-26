//
//  OCMockito - MKTClassObjectMock.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//
//  Created by: David Hart
//

#import "MKTBaseMockObject.h"


/**
    Mock object of a given class object.
 */
@interface MKTClassObjectMock : MKTBaseMockObject

+ (id)mockForClass:(Class)aClass;
- (id)initWithClass:(Class)aClass;

@end
