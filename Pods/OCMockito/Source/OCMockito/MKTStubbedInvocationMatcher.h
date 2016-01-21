//
//  OCMockito - MKTStubbedInvocationMatcher.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTInvocationMatcher.h"


@interface MKTStubbedInvocationMatcher : MKTInvocationMatcher

@property (nonatomic, strong) id answer;

@end
