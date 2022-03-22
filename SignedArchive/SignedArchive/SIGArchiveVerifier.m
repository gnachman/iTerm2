//
//  SIGArchiveVerifier.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveVerifier.h"

#import "SIGArchiveChunk.h"
#import "SIGArchiveCommon.h"
#import "SIGArchiveReader.h"
#import "SIGCertificate.h"
#import "SIGError.h"
#import "SIGKey.h"
#import "SIGPolicy.h"
#import "SIGSHA2VerificationAlgorithm.h"
#import "SIGTrust.h"
#import "SIGVerificationAlgorithm.h"

static NSInteger SIGArchiveVerifiedHighestSupportedVersion = 2;

#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
static NSInteger SIGArchiveVerifiedLowestSupportedVersion = 1;
#else
static NSInteger SIGArchiveVerifiedLowestSupportedVersion = 2;
#endif

@implementation SIGArchiveVerifier {
    SIGArchiveReader *_reader;
    NSError *_readerLoadError;
    SIGTrust *_trust;
    NSInputStream *_payloadInputStream;
    NSInputStream *_payload2InputStream;
    NSArray<SIGCertificate *> *_certificates;

#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
    NSData *_signatureData;
#endif

    NSData *_signature2Data;
    BOOL _called;
    BOOL _prepared;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
        _minimumVersion = 1;
#else
        _minimumVersion = 2;
#endif
    }
    return self;
}

- (BOOL)smellsLikeSignedArchive:(out NSError **)error {
    if (!self.reader) {
        return NO;
    }
    
    NSString *header = [self.reader header:error];
    if (!header) {
        return NO;
    }

    const BOOL ok = [header isEqualToString:SIGArchiveHeaderMagicString];
    if (error) {
        if (ok) {
            *error = nil;
        } else {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedHeader];
        }
    }
    return ok;
}

- (void)verifyWithCompletion:(void (^)(BOOL, NSError *))completion {
    assert(!_called);
    _called = YES;

    NSError *error = nil;
    if (![self prepareToVerify:&error]) {
        completion(NO, error);
        return;
    }

    [_trust evaluateWithCompletion:^(BOOL ok, NSError *error) {
        if (!ok) {
            completion(NO, error);
            return;
        }

        NSError *internalError = nil;
        const BOOL verified = [self verify:&internalError];
        self->_verified = verified;
        completion(verified, internalError);
    }];
}

- (void)verifyAndWritePayloadToURL:(NSURL *)url
                        completion:(void (^)(BOOL, NSError * _Nullable))completion {
    [self verifyWithCompletion:^(BOOL ok, NSError * _Nullable error) {
        if (!ok || error) {
            completion(ok, error);
            return;
        }

        NSError *copyError = nil;
        const BOOL copiedOK = [self copyPayloadToURL:url
                                               error:&copyError];
        completion(copiedOK, copyError);
    }];
}

- (BOOL)copyPayloadToURL:(NSURL *)url
                   error:(out NSError **)errorOut {
    if (!_verified) {
        if (errorOut) {
            *errorOut = [SIGError errorWithCode:SIGErrorCodeConsistency detail:@"Application error: archive not verified"];
        }
        return NO;
    }
    NSError *error = nil;
    NSInputStream *readStream = [_reader payloadInputStream:&error];
    if (!readStream || error) {
        if (errorOut) {
            *errorOut = error;
        }
        return NO;
    }

    [readStream open];

    NSOutputStream *writeStream = [[NSOutputStream alloc] initWithURL:url append:NO];
    if (!writeStream) {
        if (errorOut) {
            *errorOut = [SIGError errorWithCode:SIGErrorCodeIOWrite];
        }
        return NO;
    }
    [writeStream open];

    while ([readStream hasBytesAvailable]) {
        uint8_t buffer[4096];
        const NSInteger numberOfBytesRead = [readStream read:buffer maxLength:sizeof(buffer)];
        if (numberOfBytesRead == 0) {
            break;
        }
        if (numberOfBytesRead < 0) {
            if (errorOut) {
                *errorOut = [SIGError errorWithCode:SIGErrorCodeIORead];
            }
            return NO;
        }

        const NSInteger numberOfBytesWritten = [writeStream write:buffer maxLength:numberOfBytesRead];
        if (numberOfBytesWritten != numberOfBytesRead) {
            if (errorOut) {
                *errorOut = [SIGError errorWrapping:writeStream.streamError code:SIGErrorCodeIOWrite detail:nil];
            }
            return NO;
        }
    }

    if (errorOut) {
        *errorOut = nil;
    }
    return YES;
}

#pragma mark - Private

- (NSDictionary<NSString *, NSString *> *)metadataDictionaryFromString:(NSString *)metadata
                                                                 error:(out NSError **)error {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSArray<NSString *> *rows = [metadata componentsSeparatedByString:@"\n"];
    NSArray<NSString *> *knownKeys = SIGArchiveGetKnownKeys();

    for (NSString *row in rows) {
        NSInteger index = [row rangeOfString:@"="].location;
        if (index == NSNotFound) {
            continue;
        }
        NSString *key = [row substringToIndex:index];
        if (![knownKeys containsObject:key]) {
            continue;
        }
        if (dictionary[key]) {
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
            }
            return nil;
        }
        NSString *value = [row substringFromIndex:SIGAddNonnegativeInt64s(index, 1)];
        dictionary[key] = value;
    }
    return dictionary;
}

- (BOOL)verifyMetadata:(NSString *)metadata error:(out NSError **)error {
    NSDictionary *const dictionary = [self metadataDictionaryFromString:metadata
                                                                  error:error];
    if (!dictionary) {
        return NO;
    }
    NSString *const versionString = dictionary[SIGArchiveMetadataKeyVersion];
    if (!versionString) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
        }
        return NO;
    }
    NSInteger version = [versionString integerValue];
    if (version > SIGArchiveVerifiedHighestSupportedVersion) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeVersionTooNew];
        }
        return NO;
    }
    if (version < SIGArchiveVerifiedLowestSupportedVersion || version < _minimumVersion) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeDeprecatedOldVersion];
        }
        return NO;
    }

    NSString *const digestType = dictionary[SIGArchiveMetadataKeyDigestType];
    if (!digestType) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
        }
        return NO;
    }

    NSArray<NSString *> *const supportedDigestTypes = SIGVerificationDigestAlgorithmNames();
    if (![supportedDigestTypes containsObject:digestType]) {
        if (error) {
            NSString *detail = [NSString stringWithFormat:@"Algorithm \"%@\" not supported", digestType];
            *error = [SIGError errorWithCode:SIGErrorCodeUnsupportedAlgorithm detail:detail];
        }
        return NO;
    }
    return YES;
}

- (BOOL)prepareToVerify:(out NSError **)error {
    assert(!_prepared);
    _prepared = YES;

    if (!self.reader) {
        if (error) {
            *error = _readerLoadError;
        }
        return NO;
    }

    NSString *header = [_reader header:error];
    if (!header) {
        return NO;
    }
    if (![self smellsLikeSignedArchive:error]) {
        return NO;
    }
    
    NSString *metadata = [_reader metadata:error];
    if (!metadata) {
        return NO;
    }

    if (![self verifyMetadata:metadata error:error]) {
        return NO;
    }
    
    _signature2Data = [_reader signature2:error];
#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
    if (!_signature2Data) {
        _signatureData = [_reader signature:error];
        if (!_signatureData) {
            return NO;
        }
    }
#endif

    if (_signature2Data) {
        _payload2InputStream = [_reader payload2InputStream:error];
        if (!_payload2InputStream) {
            return NO;
        }
    } else {
#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
        _payloadInputStream = [_reader payloadInputStream:error];
        if (!_payloadInputStream) {
            return NO;
        }
#else
        return NO;
#endif
    }

    NSArray<NSData *> *certificateDatas = [_reader signingCertificates:error];
    if (!certificateDatas) {
        return NO;
    }
    if (certificateDatas.count == 0) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoCertificate];
        }
    }

    NSMutableArray<SIGCertificate *> *certs = [NSMutableArray array];
    for (NSData *certificateData in certificateDatas) {
        SIGCertificate *certificate = [[SIGCertificate alloc] initWithData:certificateData];
        if (!certificate) {
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeInputMalformedCertificate];
            }
            return NO;
        }
        [certs addObject:certificate];
    }
    _certificates = certs;

    SIGX509Policy *x509 = [[SIGX509Policy alloc] init];
    SIGCRLPolicy *crl = [[SIGCRLPolicy alloc] init];
    _trust = [[SIGTrust alloc] initWithCertificates:certs
                                           policies:@[ x509, crl ]
                                              error:error];
    if (!_trust) {
        return NO;
    }

    return YES;
}

- (id<SIGVerificationAlgorithm>)verificationAlgorithm:(out NSError **)error {
    id<SIGVerificationAlgorithm> algorithm = [[SIGSHA2VerificationAlgorithm alloc] init];
    if (!algorithm) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeAlgorithmCreationFailed];
        }
    }
    return algorithm;
}

- (BOOL)verify:(out NSError **)error {
    assert(_prepared);
    id<SIGVerificationAlgorithm> algorithm = [self verificationAlgorithm:error];
    if (!algorithm) {
        return NO;
    }
    if (_signature2Data) {
        return [algorithm verifyInputStream:_payload2InputStream
                              signatureData:_signature2Data
                                  publicKey:_certificates.firstObject.publicKey.secKey
                                      error:error];
    }
#if ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
    return [algorithm verifyInputStream:_payloadInputStream
                          signatureData:_signatureData
                              publicKey:_certificates.firstObject.publicKey.secKey
                                  error:error];
#else
    if (error) {
        *error = [SIGError errorWithCode:SIGErrorCodeNoSignature];
    }
    return NO;
#endif
}

- (SIGArchiveReader *)reader {
    if (!_reader && !_readerLoadError) {
        [self createReader];
    }
    return _reader;
}

- (void)createReader {
    _reader = [[SIGArchiveReader alloc] initWithURL:_url];
    if (!_reader) {
        _readerLoadError = [SIGError errorWithCode:SIGErrorCodeUnknown
                                            detail:@"Could not create archive reader"];
        return;
    }
    
    NSError *error;
    [_reader load:&error];
    _readerLoadError = error;
}

@end
