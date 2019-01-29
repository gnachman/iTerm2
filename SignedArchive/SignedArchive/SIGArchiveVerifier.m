//
//  SIGArchiveVerifier.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveVerifier.h"

#import "SIGArchiveChunk.h"
#import "SIGArchiveReader.h"
#import "SIGCertificate.h"
#import "SIGError.h"
#import "SIGKey.h"
#import "SIGPolicy.h"
#import "SIGSHA2VerificationAlgorithm.h"
#import "SIGTrust.h"
#import "SIGVerificationAlgorithm.h"

static NSInteger SIGArchiveVerifiedHighestSupportedVersion = 1;
static NSInteger SIGArchiveVerifiedLowestSupportedVersion = 1;

@implementation SIGArchiveVerifier {
    SIGArchiveReader *_reader;
    NSError *_readerLoadError;
    SIGTrust *_trust;
    NSInputStream *_payloadInputStream;
    NSArray<SIGCertificate *> *_certificates;
    NSData *_signatureData;
    BOOL _called;
    BOOL _prepared;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
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

    NSInteger numberOfBytesCopied = 0;
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

        numberOfBytesCopied += numberOfBytesWritten;
    }

    if (errorOut) {
        *errorOut = nil;
    }
    return YES;
}

#pragma mark - Private

- (NSDictionary<NSString *, NSString *> *)metadataDictionaryFromString:(NSString *)metadata {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSArray<NSString *> *rows = [metadata componentsSeparatedByString:@"\n"];
    for (NSString *row in rows) {
        NSInteger index = [row rangeOfString:@"="].location;
        if (index == NSNotFound) {
            continue;
        }
        NSString *key = [row substringToIndex:index];
        NSString *value = [row substringFromIndex:index + 1];
        dictionary[key] = value;
    }
    return dictionary;
}

- (BOOL)verifyMetadata:(NSString *)metadata error:(out NSError **)error {
    NSDictionary *const dictionary = [self metadataDictionaryFromString:metadata];
    NSString *const versionString = dictionary[@"version"];
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
    if (version < SIGArchiveVerifiedLowestSupportedVersion) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
        }
        return NO;
    }
    
    NSString *const digestType = dictionary[@"digest-type"];
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
    
    _payloadInputStream = [_reader payloadInputStream:error];
    if (!_payloadInputStream) {
        return NO;
    }

    _signatureData = [_reader signature:error];
    if (!_signatureData) {
        return NO;
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
    return [algorithm verifyInputStream:_payloadInputStream
                          signatureData:_signatureData
                              publicKey:_certificates.firstObject.publicKey.secKey
                                  error:error];
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
