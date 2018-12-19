//
//  SIGError.h
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SIGErrorDomain;

typedef NS_ENUM(NSUInteger, SIGErrorCode) {
    // Container format errors
    SIGErrorCodeInputFileMalformed,
    SIGErrorCodeMalformedMetadata,
    SIGErrorCodeVersionTooNew,
    SIGErrorCodeMalformedHeader,
    SIGErrorCodeInputMalformedCertificate,

    // Missing container chunks
    SIGErrorCodeNoPrivateKey,
    SIGErrorCodeNoCertificate,
    SIGErrorCodeNoMetadata,
    SIGErrorCodeNoSignature,
    SIGErrorCodeNoPayload,
    SIGErrorCodeNoHeader,

    // File errors
    SIGErrorCodeIORead,
    SIGErrorCodeIOWrite,

    // Internal errors
    SIGErrorCodeConsistency,
    SIGErrorCodeUnknown,

    // Algorithm aerrors
    SIGErrorCodeAlgorithmCreationFailed,
    SIGErrorCodeUnsupportedAlgorithm,

    // PKI errors
    SIGErrorCodeTrust,
    SIGErrorCodeTrustUserDeny,
    SIGErrorCodeTrustMisconfiguration,
    SIGErrorCodeTrustFailed,

    // Signature validation
    SIGErrorCodeSignatureDoesNotMatchPayload,
};

@interface SIGError : NSError

+ (instancetype)errorWithCode:(SIGErrorCode)code;
+ (instancetype)errorWithCode:(SIGErrorCode)code detail:(nullable NSString *)detail;
+ (instancetype)errorWrapping:(NSError *)otherError
                       code:(SIGErrorCode)code
                       detail:(nullable NSString *)detail;

@end

NS_ASSUME_NONNULL_END
