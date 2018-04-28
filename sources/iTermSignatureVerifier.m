//
//  iTermSignatureVerifier.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import "iTermSignatureVerifier.h"
#include <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString *const iTermSignatureVerifierErrorDomain = @"com.iterm2.signature-verifier";

@implementation iTermSignatureVerifier {
    SecKeyRef _publicSecKey;

    SecTransformRef _dataReadTransform;
    SecTransformRef _dataDigestTransform;
    SecTransformRef _dataVerifyTransform;
    SecTransformRef _dataSignTransform;
    SecGroupTransformRef _group;
}

+ (NSError *)validateFileURL:(NSURL *)url
        withEncodedSignature:(NSString *)encodedSignature
                   publicKey:(NSString *)encodedPublicKey {
    NSData *publicKeyData = [encodedPublicKey dataUsingEncoding:NSUTF8StringEncoding];
    iTermSignatureVerifier *verifier = [[self alloc] initWithPublicKeyData:publicKeyData];
    if (!verifier) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeBadPublicKeyError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not initialize verifier. Bad public key?" }];
    }

    return [verifier validateFileURL:url withEncodedSignature:encodedSignature];
}

- (instancetype)initWithPublicKeyData:(NSData *)publicKeyData {
    if (!publicKeyData) {
        return nil;
    }

    self = [super init];
    if (self) {
        SecExternalFormat format = kSecFormatOpenSSL;
        SecExternalItemType itemType = kSecItemTypePublicKey;
        CFArrayRef items = NULL;

        OSStatus status = SecItemImport((__bridge CFDataRef)publicKeyData,
                                        NULL,
                                        &format,
                                        &itemType,
                                        (SecItemImportExportFlags)0,
                                        NULL,
                                        NULL,
                                        &items);
        if (status != errSecSuccess || !items) {
            if (items) {
                CFRelease(items);
            }
            return nil;
        }

        if (format == kSecFormatOpenSSL &&
            itemType == kSecItemTypePublicKey &&
            CFArrayGetCount(items) == 1) {
            _publicSecKey = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
        }

        if (items) {
            CFRelease(items);
        }

        if (_publicSecKey == NULL) {
            return nil;
        }

        _group = SecTransformCreateGroupTransform();
        if (!_group) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_dataReadTransform) {
        CFRelease(_dataReadTransform);
    }
    if (_dataDigestTransform) {
        CFRelease(_dataDigestTransform);
    }
    if (_dataVerifyTransform) {
        CFRelease(_dataVerifyTransform);
    }
    if (_group) {
        CFRelease(_group);
    }
}

- (NSError *)validateFileURL:(NSURL *)url withEncodedSignature:(NSString *)encodedSignature {
    NSString *strippedSignature =
	[encodedSignature stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:strippedSignature
                                                            options:0];
    if (!signature) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeBase64Error
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not base-64 decode signature" }];
    }

    NSInputStream *dataInputStream = [NSInputStream inputStreamWithFileAtPath:url.path];
    if (!dataInputStream) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeFileNotFound
                                      userInfo:@{ NSLocalizedDescriptionKey: @"File not found" }];
    }

    _dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)dataInputStream);
    if (!_dataReadTransform) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeReadError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not read input file" }];
    }

    _dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA2, 256, NULL);
    if (!_dataDigestTransform) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not create SHA2 digest transform" }];
    }

    CFErrorRef secError = NULL;
    _dataVerifyTransform = SecVerifyTransformCreate(_publicSecKey, (__bridge CFDataRef)signature, &secError);
    if (!_dataVerifyTransform || secError) {
        if (secError) {
            CFRelease(secError);
        }
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not create verify transform" }];
    }
    BOOL ok;
    ok = SecTransformSetAttribute(_dataVerifyTransform, kSecInputIsAttributeName, kSecInputIsDigest, NULL );
    if (!ok) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not set input-is attribute" }];
    }

    ok = SecTransformSetAttribute(_dataVerifyTransform, kSecDigestTypeAttribute, kSecDigestSHA2, NULL );
    if (!ok) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not set digest-type attribute" }];
    }

    ok = SecTransformSetAttribute(_dataVerifyTransform, kSecDigestLengthAttribute, (__bridge CFTypeRef _Nonnull)(@256), NULL );
    if (!ok) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not set digest-length attribute" }];
    }

    SecTransformConnectTransforms(_dataReadTransform,
                                  kSecTransformOutputAttributeName,
                                  _dataDigestTransform,
                                  kSecTransformInputAttributeName,
                                  _group,
                                  &secError);
    if (secError) {
        CFRelease(secError);
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not connect data read to data digest" }];
    }

    SecTransformConnectTransforms(_dataDigestTransform,
                                  kSecTransformOutputAttributeName,
                                  _dataVerifyTransform,
                                  kSecTransformInputAttributeName,
                                  _group,
                                  &secError);
    if (secError) {
        CFRelease(secError);
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeInternalError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Could not connect data digest to data verify" }];
    }

    NSNumber *result = CFBridgingRelease(SecTransformExecute(_group, &secError));
    if (secError) {
        CFRelease(secError);
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeSignatureVerificationFailedError
                                      userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"RSA signature verification failed: %@", secError] }];
    }

    if (!result.boolValue) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeSignatureDoesNotMatchError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"RSA signature does not match. Data does not match signature or wrong public key." }];
    }

    return nil;
}

@end
