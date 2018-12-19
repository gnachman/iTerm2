//
//  SIGIdentity.h
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SIGCertificate;
@class SIGKey;

@interface SIGIdentity : NSObject

@property (nonatomic, readonly, nullable) SecIdentityRef secIdentity;
@property (nonatomic, readonly, nullable) SIGKey *privateKey;
@property (nonatomic, readonly, nullable) SIGCertificate *signingCertificate;

+ (NSArray<SIGIdentity *> *)allSigningIdentities;

- (nullable instancetype)initWithSecIdentity:(SecIdentityRef)secIdentity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
