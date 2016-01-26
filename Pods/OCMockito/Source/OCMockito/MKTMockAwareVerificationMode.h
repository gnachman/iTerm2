//
//  OCMockito - MKTMockAwareVerificationMode.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import <Foundation/Foundation.h>
#import "MKTVerificationMode.h"


@class MKTObjectMock;
@protocol MKVerificationMode;


@interface MKTMockAwareVerificationMode : NSObject <MKTVerificationMode>

+ (id)verificationWithMock:(MKTObjectMock *)mock mode:(id <MKTVerificationMode>)mode;
- (id)initWithMock:(MKTObjectMock *)mock mode:(id <MKTVerificationMode>)mode;

@end
