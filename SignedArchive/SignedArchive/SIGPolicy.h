//
//  SIGPolicy.h
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SIGPolicy<NSObject>
- (nonnull SecPolicyRef)secPolicy;
@end

@interface SIGX509Policy : NSObject<SIGPolicy>
@end

@interface SIGCRLPolicy : NSObject<SIGPolicy>
@end

NS_ASSUME_NONNULL_END
