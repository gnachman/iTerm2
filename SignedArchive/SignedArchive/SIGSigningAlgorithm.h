//
//  SIGSigningAlgorithm.h
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SIGIdentity;

@protocol SIGSigningAlgorithm<NSObject>

+ (NSString *)name;

- (nullable NSData *)signatureForInputStream:(NSInputStream *)inputStream
                               usingIdentity:(SIGIdentity *)identity
                                       error:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
