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

@interface SIGArchiveReader : NSObject

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) long long payloadLength;

- (nullable instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)load:(out NSError **)error;

- (nullable NSString *)header:(out NSError **)error;
- (nullable NSString *)metadata:(out NSError **)error;

#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
- (nullable NSData *)signature:(out NSError **)error;
#endif

- (NSData * _Nullable)signature2:(out NSError * _Nullable __autoreleasing *)error;


- (nullable NSInputStream *)payloadInputStream:(out NSError **)error;
- (nullable NSInputStream *)payload2InputStream:(out NSError **)error;
- (nullable NSArray<NSData *> *)signingCertificates:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
