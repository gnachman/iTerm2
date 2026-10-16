//
//  SIGArchiveBuilder.h
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SIGArchiveChunk.h"

NS_ASSUME_NONNULL_BEGIN

@class SIGArchivePassphraseEncryption;
@class SIGIdentity;

@interface SIGArchiveBuilder : NSObject

@property (nullable, nonatomic, readonly) NSURL *payloadFileURL;
@property (nullable, nonatomic, readonly) NSData *payloadData;
@property (nullable, nonatomic, readonly) SIGIdentity *identity;
@property (nullable, nonatomic, readonly) SIGArchivePassphraseEncryption *encryption;

- (instancetype)initWithPayloadFileURL:(NSURL *)payloadFileURL
                              identity:(SIGIdentity *)identity;

// Exactly one of identity and encryption must be nonnil. With encryption, the payload is sealed
// with a passphrase-derived key and the archive is unsigned. With an identity, the archive is
// signed. Use this to keep a sensitive payload off the disk.
- (instancetype)initWithPayloadData:(NSData *)payloadData
                           identity:(nullable SIGIdentity *)identity
                         encryption:(nullable SIGArchivePassphraseEncryption *)encryption;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)writeToURL:(NSURL *)url
             error:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
