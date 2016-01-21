//
//  OCMockito - MKTInvocationContainer.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import <Foundation/Foundation.h>

@class MKTMockingProgress;
@protocol HCMatcher;


@interface MKTInvocationContainer : NSObject

@property (nonatomic, readonly) NSMutableArray *registeredInvocations;

- (id)initWithMockingProgress:(MKTMockingProgress *)mockingProgress;
- (void)setInvocationForPotentialStubbing:(NSInvocation *)invocation;
- (void)setMatcher:(id <HCMatcher>)matcher atIndex:(NSUInteger)argumentIndex;
- (void)addAnswer:(id)answer;
- (id)findAnswerFor:(NSInvocation *)invocation;

@end
