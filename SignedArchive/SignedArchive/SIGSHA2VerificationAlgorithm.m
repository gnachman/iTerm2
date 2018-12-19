//
//  SIGSHA2VerificationAlgorithm.m
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGSHA2VerificationAlgorithm.h"

#import "SIGError.h"
#import "SIGVerificationAlgorithm.h"

@implementation SIGSHA2VerificationAlgorithm {
    SecTransformRef _dataReadTransform;
    SecTransformRef _dataDigestTransform;
    SecTransformRef _dataVerifyTransform;
    SecGroupTransformRef _group;
}

+ (NSString *)name {
    return @"SHA2";
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

- (BOOL)verifyInputStream:(NSInputStream *)payloadInputStream
            signatureData:(NSData *)signatureData
                publicKey:(SecKeyRef)publicKey
                    error:(out NSError **)error {
    _dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)payloadInputStream);
    if (!_dataReadTransform) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnknown];
        }
        return NO;
    }
    
    _dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA2,
                                                    256,
                                                    NULL);
    if (!_dataDigestTransform) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnknown];
        }
        return NO;
    }
    
    CFErrorRef secError = NULL;
    _dataVerifyTransform = SecVerifyTransformCreate(publicKey,
                                                    (__bridge CFDataRef)signatureData,
                                                    &secError);
    if (!_dataVerifyTransform || secError) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)secError
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create data verification transform"];
        }
        if (secError) {
            CFRelease(secError);
        }
        return NO;
    }
    
    BOOL ok;
    ok = SecTransformSetAttribute(_dataVerifyTransform,
                                  kSecInputIsAttributeName,
                                  kSecInputIsDigest,
                                  NULL);
    if (!ok) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnknown];
        }
        return NO;
    }
    
    ok = SecTransformSetAttribute(_dataVerifyTransform,
                                  kSecDigestTypeAttribute,
                                  kSecDigestSHA2,
                                  NULL);
    if (!ok) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnknown];
        }
        return NO;
    }
    
    ok = SecTransformSetAttribute(_dataVerifyTransform,
                                  kSecDigestLengthAttribute,
                                  (__bridge CFTypeRef _Nonnull)(@256),
                                  NULL);
    if (!ok) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnknown];
        }
        return NO;
    }
    
    _group = SecTransformCreateGroupTransform();
    SecTransformConnectTransforms(_dataReadTransform,
                                  kSecTransformOutputAttributeName,
                                  _dataDigestTransform,
                                  kSecTransformInputAttributeName,
                                  _group,
                                  &secError);
    if (secError) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)secError
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to connect read to digest transform"];
        }
        CFRelease(secError);
        return NO;
    }
    
    SecTransformConnectTransforms(_dataDigestTransform,
                                  kSecTransformOutputAttributeName,
                                  _dataVerifyTransform,
                                  kSecTransformInputAttributeName,
                                  _group,
                                  &secError);
    if (secError) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)secError
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to connect digest to verify transform"];
        }
        CFRelease(secError);
        return NO;
    }
    
    NSNumber *result = (__bridge_transfer NSNumber *)SecTransformExecute(_group, &secError);
    if (secError) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)secError
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to execute verification"];
        }
        CFRelease(secError);
        return NO;
    }
    
    if (!result.boolValue) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeSignatureDoesNotMatchPayload];
        }
        return NO;
    }
    
    return YES;
}

@end
