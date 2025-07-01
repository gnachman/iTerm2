//
//  SIGSHA2SigningAlgorithm.m
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGSHA2SigningAlgorithm.h"

#import "SIGArchiveCommon.h"
#import "SIGError.h"
#import "SIGIdentity.h"
#import "SIGKey.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation SIGSHA2SigningAlgorithm

+ (NSString *)name {
    return SIGArchiveDigestTypeSHA2;
}

- (NSData *)signatureForInputStream:(NSInputStream *)readStream
                      usingIdentity:(SIGIdentity *)identity
                              error:(out NSError **)error {
    SIGKey *privateKey = identity.privateKey;
    if (!privateKey) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPrivateKey];
        }
        return nil;
    }

    [readStream open];

    CC_SHA256_CTX shaCtx;
    CC_SHA256_Init(&shaCtx);

    uint8_t buffer[4096];
    NSInteger bytesRead = 0;
    while ((bytesRead = [readStream read:buffer
                              maxLength:sizeof(buffer)]) > 0) {
        CC_SHA256_Update(&shaCtx,
                         buffer,
                         (CC_LONG)bytesRead);
    }

    [readStream close];

    if (bytesRead < 0) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeAlgorithmCreationFailed
                                     detail:@"Error reading input stream"];
        }
        return nil;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &shaCtx);

    CFDataRef digestData = CFDataCreate(kCFAllocatorDefault,
                                        digest,
                                        CC_SHA256_DIGEST_LENGTH);

    SecKeyRef key = privateKey.secKey;
    SecKeyAlgorithm algorithm = kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256;

    if (!SecKeyIsAlgorithmSupported(key,
                                    kSecKeyOperationTypeSign,
                                    algorithm)) {
        CFRelease(digestData);
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeAlgorithmCreationFailed
                                     detail:@"Key does not support requested algorithm"];
        }
        return nil;
    }

    CFErrorRef cfErr = NULL;
    CFDataRef  sigCFData = SecKeyCreateSignature(key,
                                                 algorithm,
                                                 digestData,
                                                 &cfErr);
    CFRelease(digestData);

    if (!sigCFData) {
        NSError *underlying = CFBridgingRelease(cfErr);
        if (error) {
            *error = [SIGError errorWrapping:underlying
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                    detail:@"Signing failed"];
        }
        return nil;
    }

    NSData *signature = CFBridgingRelease(sigCFData);
    return signature;
}

@end
