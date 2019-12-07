//
//  SIGArchiveBuilder.m
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveBuilder.h"

#import "SIGArchiveChunk.h"
#import "SIGArchiveCommon.h"
#import "SIGArchiveVerifier.h"
#import "SIGCertificate.h"
#import "SIGError.h"
#import "SIGIdentity.h"
#import "SIGKey.h"
#import "SIGSHA2SigningAlgorithm.h"

@implementation SIGArchiveBuilder {
    long long _offset;
}

- (instancetype)initWithPayloadFileURL:(NSURL *)url
                              identity:(SIGIdentity *)identity {
    self = [super init];
    if (self) {
        _payloadFileURL = url;
        _identity = identity;
    }
    return self;
}

#pragma mark - API

- (BOOL)writeToURL:(NSURL *)url
             error:(out NSError * _Nullable __autoreleasing *)error {
#if ENABLE_SIGARCHIVE_MIGRATION_CREATION
    NSData *signature = [self signature:error];
    if (!signature) {
        return NO;
    }
#endif
    NSData *certificate = _identity.signingCertificate.data;
    if (!certificate) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoCertificate];
        }
        return NO;
    }

    // Write everything but the signature to a buffer in memory.
    NSOutputStream *combinedOutputStream = [NSOutputStream outputStreamToMemory];
    if (!combinedOutputStream) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIOWrite detail:@"Could not create write stream"];
        }
        return NO;
    }
    [combinedOutputStream open];

    if (![self writeHeaderToStream:combinedOutputStream error:error]) {
        return NO;
    }
    if (![self writeMetadataToStream:combinedOutputStream error:error]) {
        return NO;
    }
    if (![self writePayloadToStream:combinedOutputStream error:error]) {
        return NO;
    }
#if ENABLE_SIGARCHIVE_MIGRATION_CREATION
    if (![self writeSignature:signature toStream:combinedOutputStream error:error]) {
        return NO;
    }
#endif
    if (![self writeCertificate:certificate toStream:combinedOutputStream error:error]) {
        return NO;
    }

    // NOTE: The signing certificate must be first. This is a requirement of SecTrustCreateWithCertificates
    // which is implicit in the file format.
    SIGCertificate *issuerCertificate = _identity.signingCertificate.issuer;
    while (issuerCertificate != nil) {
        if (![self writeCertificate:issuerCertificate.data toStream:combinedOutputStream error:error]) {
            return NO;
        }
        if ([issuerCertificate.issuer isEqual:issuerCertificate]) {
            break;
        }
        issuerCertificate = issuerCertificate.issuer;
    }
    [combinedOutputStream close];

    // Now compute the signature of that buffer.
    NSData *combinedData = [combinedOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    if (!combinedData) {
        return NO;
    }
    NSData *signature2 = [self signatureForData:combinedData error:error];
    if (!signature2) {
        return NO;
    }

    // Concatenate the combined data and the signature chunk to a file on disk.
    NSOutputStream *writeStream = [NSOutputStream outputStreamWithURL:url append:NO];
    [writeStream open];
    const long long length = [writeStream write:combinedData.bytes maxLength:combinedData.length];
    if (length != combinedData.length) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIOWrite];
        }
        return NO;
    }
    if (![self writeSignature2:signature2 toStream:writeStream error:error]) {
        return NO;
    }
    [writeStream close];

    return YES;
}

#pragma mark - Write Chunks

- (BOOL)writeHeaderToStream:(NSOutputStream *)stream error:(out NSError * _Nullable __autoreleasing *)error {
    NSData *data = [SIGArchiveHeaderMagicString dataUsingEncoding:NSUTF8StringEncoding];
    const NSInteger desiredLength = data.length;
    SIGArchiveChunkWriter *chunkWriter = [[SIGArchiveChunkWriter alloc] initWithTag:SIGArchiveTagHeader
                                                                             length:desiredLength
                                                                             offset:_offset];
    const BOOL ok = [chunkWriter writeData:data
                                  toStream:stream
                                     error:error];
    _offset += chunkWriter.chunkLength;
    return ok;
}

- (BOOL)writePayloadToStream:(NSOutputStream *)writeStream error:(out NSError * _Nullable __autoreleasing *)errorOut {
    NSInputStream *readStream = [[NSInputStream alloc] initWithURL:_payloadFileURL];
    if (!readStream) {
        return NO;
    }
    [readStream open];
    
    NSError *error = nil;
    NSInteger length = [[NSFileManager defaultManager] attributesOfItemAtPath:_payloadFileURL.path error:&error].fileSize;
    if (length <= 0 || error != nil) {
        if (errorOut) {
            *errorOut = [SIGError errorWrapping:error
                                         code:SIGErrorCodeIORead
                                         detail:@"Error checking file size"];
        }
        return NO;
    }
    SIGArchiveChunkWriter *chunkWriter = [[SIGArchiveChunkWriter alloc] initWithTag:SIGArchiveTagPayload
                                                                             length:length
                                                                             offset:_offset];
    const BOOL ok = [chunkWriter writeStream:readStream
                                    toStream:writeStream
                                       error:errorOut];
    _offset += chunkWriter.chunkLength;
    return ok;
}

- (NSString *)keyValuePairsFromDictionary:(NSDictionary<NSString *, NSString *> *)dictionary {
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        [entries addObject:[NSString stringWithFormat:@"%@=%@", key, obj]];
    }];
    return [entries componentsJoinedByString:@"\n"];
}

- (NSString *)producedVersion {
    // Version 1 signed only the payload. Version 2 signs the container except the signature's chunk.
#if ENABLE_SIGARCHIVE_MIGRATION_CREATION
    return @"1";
#else
    return @"2";
#endif
}

- (NSString *)producedDigestType {
    return [[self signingAlgorithmClass] name];
}

- (BOOL)writeMetadataToStream:(NSOutputStream *)writeStream error:(out NSError * _Nullable __autoreleasing *)error {
    NSDictionary *const fieldDict = @{ SIGArchiveMetadataKeyVersion: [self producedVersion],
                                       SIGArchiveMetadataKeyDigestType: [self producedDigestType] };
    NSString *metadata = [self keyValuePairsFromDictionary:fieldDict];
    NSData *data = [metadata dataUsingEncoding:NSUTF8StringEncoding];
    SIGArchiveChunkWriter *chunkWriter = [[SIGArchiveChunkWriter alloc] initWithTag:SIGArchiveTagMetadata
                                                                             length:data.length
                                                                             offset:_offset];
    const BOOL ok = [chunkWriter writeData:data
                                  toStream:writeStream
                                     error:error];
    _offset += chunkWriter.chunkLength;
    return ok;
}

#if ENABLE_SIGARCHIVE_MIGRATION_CREATION
- (BOOL)writeSignature:(NSData *)signature toStream:(NSOutputStream *)writeStream error:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunkWriter *chunkWriter = [[SIGArchiveChunkWriter alloc] initWithTag:SIGArchiveTagSignature
                                                                             length:signature.length
                                                                             offset:_offset];
    const BOOL ok = [chunkWriter writeData:signature
                                  toStream:writeStream
                                     error:error];
    _offset += chunkWriter.chunkLength;
    return ok;
}
#endif

- (BOOL)writeSignature2:(NSData *)signature toStream:(NSOutputStream *)writeStream error:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunkWriter *chunkWriter = [[SIGArchiveChunkWriter alloc] initWithTag:SIGArchiveTagSignature2
                                                                             length:signature.length
                                                                             offset:_offset];
    const BOOL ok = [chunkWriter writeData:signature
                                  toStream:writeStream
                                     error:error];
    _offset += chunkWriter.chunkLength;
    return ok;
}

- (BOOL)writeCertificate:(NSData *)certificate toStream:(NSOutputStream *)writeStream error:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunkWriter *chunkWriter = [[SIGArchiveChunkWriter alloc] initWithTag:SIGArchiveTagCertificate
                                                                             length:certificate.length
                                                                             offset:_offset];
    const BOOL ok = [chunkWriter writeData:certificate
                                  toStream:writeStream
                                     error:error];
    _offset += chunkWriter.chunkLength;
    return ok;
}

#pragma mark - Signing

- (Class)signingAlgorithmClass {
    return [SIGSHA2SigningAlgorithm class];
}

- (id<SIGSigningAlgorithm>)signingAlgorithm:(out NSError **)error {
    id<SIGSigningAlgorithm> algorithm = [[[self signingAlgorithmClass] alloc] init];
    if (!algorithm) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeAlgorithmCreationFailed];
        }
    }
    return algorithm;
}

#if ENABLE_SIGARCHIVE_MIGRATION_CREATION
- (NSData *)signature:(out NSError **)error {
    id<SIGSigningAlgorithm> algorithm = [self signingAlgorithm:error];
    if (!algorithm) {
        return nil;
    }

    NSInputStream *readStream = [NSInputStream inputStreamWithFileAtPath:_payloadFileURL.path];
    if (!readStream) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIORead];
        }
        return nil;
    }

    return [algorithm signatureForInputStream:readStream
                                usingIdentity:_identity
                                        error:error];
}
#endif

- (NSData *)signatureForData:(NSData *)data error:(out NSError **)error {
    id<SIGSigningAlgorithm> algorithm = [self signingAlgorithm:error];
    if (!algorithm) {
        return nil;
    }

    NSInputStream *readStream = [NSInputStream inputStreamWithData:data];
    if (!readStream) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIORead];
        }
        return nil;
    }
    
    return [algorithm signatureForInputStream:readStream
                                usingIdentity:_identity
                                        error:error];
}

@end
