//
//  SIGArchiveReader.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SIGArchiveReader : NSObject

@property (nonatomic, readonly) NSURL *url;

- (nullable instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)load:(out NSError **)error;

- (nullable NSString *)header:(out NSError **)error;
- (nullable NSString *)metadata:(out NSError **)error;
- (nullable NSData *)signature:(out NSError **)error;
- (nullable NSInputStream *)payloadInputStream:(out NSError **)error;
- (nullable NSData *)signingCertificate:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
