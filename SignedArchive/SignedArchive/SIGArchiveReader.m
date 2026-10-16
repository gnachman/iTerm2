//
//  SIGArchiveReader.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveReader.h"

#import "SIGArchiveBuilder.h"
#import "SIGArchiveChunk.h"
#import "SIGArchiveCommon.h"
#import "SIGArchiveEncryption.h"
#import "SIGError.h"
#import "SIGPartialInputStream.h"

@implementation SIGArchiveReader {
    NSArray<SIGArchiveChunk *> *_chunks;
    BOOL _loaded;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        if (!url) {
            return nil;
        }
        _url = url;
        _minimumKDFIterations = SIGArchiveEncryptionMinimumIterations;
    }
    return self;
}

- (NSString *)header:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagHeader];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoHeader];
        }
        return nil;
    }

    if (chunk != _chunks.firstObject) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedHeader];
        }
        return nil;
    }

    NSData *data = [chunk data:error];
    if (!data) {
        return nil;
    }

    NSString *string = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
    if (!string) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedHeader];
        }
        return nil;
    }
    
    return string;
}

- (NSString *)metadata:(out NSError **)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagMetadata];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoMetadata];
        }
        return nil;
    }
    NSData *data = [chunk data:error];
    if (!data) {
        return nil;
    }
    NSString *string = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
    if (!string) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
        }
        return nil;
    }
    
    return string;
}

- (NSDictionary<NSString *, NSString *> *)metadataDictionary:(out NSError **)error {
    NSString *metadata = [self metadata:error];
    if (!metadata) {
        return nil;
    }
    return SIGArchiveParseMetadata(metadata, error);
}

- (BOOL)isEncrypted {
    return [self metadataDictionary:nil][SIGArchiveMetadataKeyEncryption] != nil;
}

- (NSData *)decryptedPayloadWithPassphrase:(NSString *)passphrase
                                    cipher:(id<SIGAuthenticatedCipher>)cipher
                                     error:(out NSError **)error {
    NSString *header = [self header:error];
    if (!header) {
        return nil;
    }
    if (![header isEqualToString:SIGArchiveHeaderMagicString]) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedHeader];
        }
        return nil;
    }
    NSDictionary<NSString *, NSString *> *metadata = [self metadataDictionary:error];
    if (!metadata) {
        return nil;
    }
    if (!metadata[SIGArchiveMetadataKeyEncryption]) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNotEncrypted];
        }
        return nil;
    }
    if ([metadata[SIGArchiveMetadataKeyVersion] integerValue] > 2) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeVersionTooNew];
        }
        return nil;
    }
    SIGArchivePassphraseEncryption *encryption =
        [[SIGArchivePassphraseEncryption alloc] initWithPassphrase:passphrase
                                                            cipher:cipher
                                                          metadata:metadata
                                                 minimumIterations:_minimumKDFIterations
                                                             error:error];
    if (!encryption) {
        return nil;
    }
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagPayload];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPayload];
        }
        return nil;
    }
    // The AAD is everything before the payload, so the metadata must be in it.
    if ([self chunkWithTag:SIGArchiveTagMetadata].payloadOffset > chunk.payloadOffset) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeInputFileMalformed];
        }
        return nil;
    }
    NSData *sealedBox = [chunk data:error];
    if (!sealedBox) {
        return nil;
    }
    NSData *aad = [self dataInRange:NSMakeRange(0, chunk.payloadOffset) error:error];
    if (!aad) {
        return nil;
    }
    NSData *key = [encryption derivedKey:error];
    if (!key) {
        return nil;
    }
    NSData *plaintext = [cipher openSealedBox:sealedBox key:key aad:aad error:nil];
    if (!plaintext) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeDecryptionFailed];
        }
        return nil;
    }
    return plaintext;
}

#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
- (NSData *)signature:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagSignature];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoSignature];
        }
        return nil;
    }
    return [chunk data:error];
}
#endif

- (NSData *)signature2:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunk *chunk = [self lastChunk];
    if (chunk.tag != SIGArchiveTagSignature2) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoSignature];
        }
        return nil;
    }
    return [chunk data:error];
}

- (NSArray<NSData *> *)signingCertificates:(out NSError * _Nullable __autoreleasing *)error {
    NSArray<SIGArchiveChunk *> *chunks = [self chunksWithTag:SIGArchiveTagCertificate];
    if (!chunks.count) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoCertificate];
        }
        return nil;
    }
    NSMutableArray<NSData *> *datas = [NSMutableArray array];
    for (SIGArchiveChunk *chunk in chunks) {
        NSData *data = [chunk data:error];
        if (!data) {
            return nil;
        }
        [datas addObject:data];
    }
    return datas;
}

- (NSInputStream *)payloadInputStream:(out NSError **)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagPayload];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPayload];
        }
        return nil;
    }
    return [[SIGPartialInputStream alloc] initWithURL:_url
                                                range:NSMakeRange(chunk.payloadOffset,
                                                                  chunk.payloadLength)];
}

- (NSInputStream *)payload2InputStream:(out NSError **)error {
    // The last chunk is the signature. It signs the chunks that precede it. Find the chunk before
    // the signature to establish the number of bytes to sign.
    SIGArchiveChunk *chunk = [self penultimateChunk];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPayload];
        }
        return nil;
    }

    const long long length = SIGAddNonnegativeInt64s([chunk payloadOffset], [chunk payloadLength]);
    if (length <= 0) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPayload];
        }
        return nil;
    }

    return [[SIGPartialInputStream alloc] initWithURL:_url
                                                range:NSMakeRange(0, length)];
}

- (long long)payloadLength {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagPayload];
    if (!chunk) {
        return 0;
    }
    return chunk.payloadLength;
}

- (BOOL)load:(out NSError **)errorOut {
    assert(!_loaded);
    _loaded = YES;
    
    NSError *error = nil;
    const NSInteger length = [[NSFileManager defaultManager] attributesOfItemAtPath:_url.path
                                                                              error:&error].fileSize;
    if (error) {
        if (errorOut) {
            *errorOut = [SIGError errorWrapping:error
                                           code:SIGErrorCodeIORead
                                         detail:@"Failed get get size of input file"];
        }
        return NO;
    }

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:_url
                                                                   error:&error];
    if (!fileHandle) {
        if (errorOut) {
            *errorOut = [SIGError errorWrapping:error
                                           code:SIGErrorCodeIORead
                                         detail:@"Error opening file"];
        }
        return NO;
    }
    NSMutableArray<SIGArchiveChunk *> *chunks = [NSMutableArray array];
    NSInteger offset = 0;
    while (offset < length) {
        SIGArchiveChunk *chunk = [SIGArchiveChunk chunkFromFileHandle:fileHandle
                                                             atOffset:offset
                                                                error:errorOut];
        if (!chunk) {
            return NO;
        }
        [chunks addObject:chunk];
        offset = SIGAddNonnegativeInt64s(chunk.payloadOffset, chunk.payloadLength);
    }
    if (offset > length) {
        if (errorOut) {
            *errorOut = [SIGError errorWithCode:SIGErrorCodeInputFileMalformed];
        }
        return NO;
    }
    _chunks = [chunks copy];
    return YES;
}

#pragma mark - Private

- (NSData *)dataInRange:(NSRange)range error:(out NSError **)error {
    NSError *openError = nil;
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:_url error:&openError];
    if (!fileHandle) {
        if (error) {
            *error = [SIGError errorWrapping:openError code:SIGErrorCodeIORead detail:@"Error opening file"];
        }
        return nil;
    }
    NSData *data = nil;
    @try {
        [fileHandle seekToFileOffset:range.location];
        data = [fileHandle readDataOfLength:range.length];
    } @catch (NSException *exception) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIORead detail:exception.reason];
        }
        return nil;
    }
    if (data.length != range.length) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIORead detail:@"Short read"];
        }
        return nil;
    }
    return data;
}

- (SIGArchiveChunk *)lastChunk {
    return _chunks.lastObject;
}

- (SIGArchiveChunk *)penultimateChunk {
    if (_chunks.count < 2) {
        return nil;
    }
    return _chunks[_chunks.count - 2];
}

- (SIGArchiveChunk *)chunkWithTag:(SIGArchiveTag)tag {
    NSInteger index = [_chunks indexOfObjectPassingTest:^BOOL(SIGArchiveChunk * _Nonnull obj,
                                                              NSUInteger idx,
                                                              BOOL * _Nonnull stop) {
        return obj.tag == tag;
    }];

    if (index == NSNotFound) {
        return nil;
    }

    return _chunks[index];
}

- (NSArray<SIGArchiveChunk *> *)chunksWithTag:(SIGArchiveTag)tag {
    NSIndexSet *indexes = [_chunks indexesOfObjectsPassingTest:^BOOL(SIGArchiveChunk * _Nonnull obj,
                                                                     NSUInteger idx,
                                                                     BOOL * _Nonnull stop) {
        return obj.tag == tag;
    }];

    return [_chunks objectsAtIndexes:indexes];
}

@end
