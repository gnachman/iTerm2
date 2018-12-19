//
//  SIGCertificate.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SIGKey;

@interface SIGCertificate : NSObject

@property (nonatomic, readonly, nullable) SecCertificateRef secCertificate;
@property (nonatomic, readonly, nullable) NSData *data;
@property (nonatomic, readonly, nullable) SIGKey *publicKey;
@property (nonatomic, readonly, nullable) NSString *longDescription;
@property (nonatomic, readonly, nullable) NSString *name;
@property (nonatomic, readonly, nullable) NSData *serialNumber;

- (nullable instancetype)initWithSecCertificate:(SecCertificateRef)secCertificate NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithData:(NSData *)data NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
