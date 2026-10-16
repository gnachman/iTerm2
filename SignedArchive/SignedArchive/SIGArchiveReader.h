//
//  SIGArchiveReader.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SIGArchiveCommon.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SIGAuthenticatedCipher;

@interface SIGArchiveReader : NSObject

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) long long payloadLength;
// Defaults to SIGArchiveEncryptionMinimumIterations. Lowered only by tests.
@property (nonatomic) unsigned int minimumKDFIterations;

- (nullable instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)load:(out NSError **)error;

- (nullable NSString *)header:(out NSError **)error;
- (nullable NSString *)metadata:(out NSError **)error;
- (nullable NSDictionary<NSString *, NSString *> *)metadataDictionary:(out NSError **)error;

// Whether the metadata declares an encrypted payload. Returns NO if the metadata can't be read.
- (BOOL)isEncrypted;

// Authenticates and decrypts an encrypted archive's payload. This does not check a signature, if
// one is present; use SIGArchiveVerifier for that.
- (nullable NSData *)decryptedPayloadWithPassphrase:(NSString *)passphrase
                                             cipher:(id<SIGAuthenticatedCipher>)cipher
                                              error:(out NSError **)error;

#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
- (nullable NSData *)signature:(out NSError **)error;
#endif

- (NSData * _Nullable)signature2:(out NSError * _Nullable __autoreleasing *)error;


- (nullable NSInputStream *)payloadInputStream:(out NSError **)error;
- (nullable NSInputStream *)payload2InputStream:(out NSError **)error;
- (nullable NSArray<NSData *> *)signingCertificates:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
