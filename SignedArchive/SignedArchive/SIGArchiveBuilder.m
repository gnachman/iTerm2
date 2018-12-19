//
//  SIGArchiveBuilder.m
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveBuilder.h"

#import "SIGArchiveChunk.h"
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
    NSData *signature = [self signature:error];
    if (!signature) {
        return NO;
    }
    
    NSData *certificate = _identity.signingCertificate.data;
    if (!certificate) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoCertificate];
        }
        return NO;
    }

    NSOutputStream *writeStream = [NSOutputStream outputStreamWithURL:url append:NO];
    if (!writeStream) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIOWrite detail:@"Could not create write stream"];
        }
        return NO;
    }
    [writeStream open];
    
    if (![self writeHeaderToStream:writeStream error:error]) {
        return NO;
    }
    if (![self writeMetadataToStream:writeStream error:error]) {
        return NO;
    }
    if (![self writePayloadToStream:writeStream error:error]) {
        return NO;
    }
    if (![self writeSignature:signature toStream:writeStream error:error]) {
        return NO;
    }
    if (![self writeCertificate:certificate toStream:writeStream error:error]) {
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

- (BOOL)writeMetadataToStream:(NSOutputStream *)writeStream error:(out NSError * _Nullable __autoreleasing *)error {
    NSArray<NSString *> *fields = @[ @"version=1",
                                     @"digest-type=SHA2" ];
    NSString *metadata = [fields componentsJoinedByString:@"\n"];
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

- (id<SIGSigningAlgorithm>)signingAlgorithm:(out NSError **)error {
    id<SIGSigningAlgorithm> algorithm = [[SIGSHA2SigningAlgorithm alloc] init];
    if (!algorithm) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeAlgorithmCreationFailed];
        }
    }
    return algorithm;
}

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

@end
