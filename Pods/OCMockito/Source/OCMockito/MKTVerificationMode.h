//
//  OCMockito - MKTVerificationMode.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import <Foundation/Foundation.h>

@class MKTVerificationData;


@protocol MKTVerificationMode <NSObject>

- (void)verifyData:(MKTVerificationData *)data;

@end
