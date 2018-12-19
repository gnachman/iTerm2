//
//  SIGVerificationAlgorithm.h
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSArray<NSString *> *SIGVerificationDigestAlgorithmNames(void);

@protocol SIGVerificationAlgorithm<NSObject>

+ (NSString *)name;

- (BOOL)verifyInputStream:(NSInputStream *)payloadInputStream
            signatureData:(NSData *)signatureData
                publicKey:(SecKeyRef)publicKey
                    error:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
