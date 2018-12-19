//
//  SIGTrust.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SIGCertificate;
@protocol SIGPolicy;

@interface SIGTrust : NSObject

@property (nonatomic, readonly) SecTrustRef secTrust;
@property (nonatomic, readonly) NSArray<SIGCertificate *> *certificates;
@property (nonatomic, readonly) NSArray<id<SIGPolicy>> *policies;

- (instancetype)initWithCertificates:(NSArray<SIGCertificate *> *)certificates
                            policies:(NSArray<id<SIGPolicy>> *)policies
                               error:(out NSError **)error NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// NOTE: The completion block is run off the main queue.
- (void)evaluateWithCompletion:(void (^)(BOOL ok, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
