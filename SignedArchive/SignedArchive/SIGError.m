//
//  SIGError.m
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGError.h"

NSString *const SIGErrorDomain = @"com.iterm2.sig";

@implementation SIGError

+ (instancetype)errorWithCode:(SIGErrorCode)code {
    NSString *localizedDescription = [self localizedDescriptionFcode:code];
    return [SIGError errorWithDomain:SIGErrorDomain
                                code:code
                            userInfo:@{ NSLocalizedDescriptionKey: [localizedDescription stringByAppendingString:@"."] }];
}

+ (instancetype)errorWithCode:(SIGErrorCode)code detail:(NSString *)detail {
    if (!detail) {
        return [self errorWithCode:code];
    }
    return [SIGError errorWithDomain:SIGErrorDomain
                                code:code
                            userInfo:@{ NSLocalizedDescriptionKey: [detail stringByAppendingString:@"."] }];
}

+ (instancetype)errorWrapping:(NSError *)otherError code:(SIGErrorCode)code detail:(NSString *)detail {
    if (!otherError) {
        return [self errorWithCode:code detail:detail];
    }

    if (!detail) {
        return [self errorWrapping:otherError code:code detail:[self localizedDescriptionFcode:code]];
    }

    NSString *innerDetail = otherError.localizedDescription ?: [NSString stringWithFormat:@"%@ error code %@",
                                                                otherError.domain, @(otherError.code)];
    NSString *description = [NSString stringWithFormat:@"%@: %@", detail, innerDetail];
    return [self errorWithCode:code detail:description];
}

#pragma mark - Private

+ (NSString *)localizedDescriptionFcode:(SIGErrorCode)code {
    switch (code) {
        case SIGErrorCodeConsistency:
            return @"Inconsistency discovered";
        case SIGErrorCodeIOWrite:
            return @"Error writing destination file";
        case SIGErrorCodeIORead:
            return @"Error reading source file";
        case SIGErrorCodeNoPrivateKey:
            return @"No private key found";
        case SIGErrorCodeNoCertificate:
            return @"No certificate found";
        case SIGErrorCodeNoMetadata:
            return @"No metadata found";
        case SIGErrorCodeNoSignature:
            return @"No signature found";
        case SIGErrorCodeNoPayload:
            return @"No payload found";
        case SIGErrorCodeNoHeader:
            return @"No header found";
        case SIGErrorCodeAlgorithmCreationFailed:
            return @"Could not create algorithm";
        case SIGErrorCodeVersionTooNew:
            return @"Source file from a future version";
        case SIGErrorCodeMalformedMetadata:
            return @"Metadata chunk malformed";
        case SIGErrorCodeMalformedHeader:
            return @"Header chunk malformed";
        case SIGErrorCodeUnsupportedAlgorithm:
            return @"Unsupported algorithm";
        case SIGErrorCodeUnknown:
            return @"Unknown or unexpected error";
        case SIGErrorCodeInputFileMalformed:
            return @"Input file malformed";
        case SIGErrorCodeInputMalformedCertificate:
            return @"Malformed certificate";
        case SIGErrorCodeTrust:
            return @"Error creating trust object";
        case SIGErrorCodeTrustUserDeny:
            return @"Trust chain verification failed by user preference";
        case SIGErrorCodeTrustMisconfiguration:
            return @"Trust chain verification internal error";
        case SIGErrorCodeTrustFailed:
            return @"Trust chain verification failed";
        case SIGErrorCodeSignatureDoesNotMatchPayload:
            return @"Signature does not match payload";
    }
    return @"Unknown error";
}

@end
