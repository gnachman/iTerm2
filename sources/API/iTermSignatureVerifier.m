//
//  iTermSignatureVerifier.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import "iTermSignatureVerifier.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString *const iTermSignatureVerifierErrorDomain = @"com.iterm2.signature-verifier";

@implementation iTermSignatureVerifier {
    SecKeyRef _publicKey;
}

+ (NSError *)validateFileURL:(NSURL *)url
        withEncodedSignature:(NSString *)encodedSignature
                   publicKey:(NSString *)encodedPublicKey {
    NSData *publicKeyData = [self derKeyDataFromPEMString:encodedPublicKey];
    if (!publicKeyData) {
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeBadPublicKeyError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Invalid public key format" }];
    }

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
        CFErrorRef err = NULL;
        NSDictionary *opts = @{
            (__bridge id)kSecAttrKeyType : (__bridge id)kSecAttrKeyTypeRSA,
            (__bridge id)kSecAttrKeyClass : (__bridge id)kSecAttrKeyClassPublic,
        };

        _publicKey = SecKeyCreateWithData((__bridge CFDataRef)publicKeyData,
                                          (__bridge CFDictionaryRef)opts,
                                          &err);
        if (!_publicKey || err) {
            if (err) {
                CFRelease(err);
            }
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_publicKey) {
        CFRelease(_publicKey);
    }
}

- (NSData *)sha256DigestOfFileAtURL:(NSURL *)url error:(NSError **)error {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    if (stream.streamStatus != NSStreamStatusOpen) {
        if (error) {
            *error = [NSError errorWithDomain:iTermSignatureVerifierErrorDomain
                                         code:iTermSignatureVerifierErrorCodeFileNotFound
                                     userInfo:@{ NSLocalizedDescriptionKey : @"File not found" }];
        }
        return nil;
    }

    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);

    uint8_t buffer[4096];
    NSInteger read;
    while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
        CC_SHA256_Update(&ctx, buffer, (CC_LONG)read);
    }

    [stream close];
    if (read < 0) {
        if (error) {
            *error = [NSError errorWithDomain:iTermSignatureVerifierErrorDomain
                                         code:iTermSignatureVerifierErrorCodeReadError
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Could not read input file" }];
        }
        return nil;
    }


    unsigned char digestBytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digestBytes, &ctx);

    return [NSData dataWithBytes:digestBytes
                          length:CC_SHA256_DIGEST_LENGTH];
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

    NSError *digestErr = nil;
    NSData *digest = [self sha256DigestOfFileAtURL:url error:&digestErr];
    if (!digest) {
        return digestErr;
    }

    CFErrorRef secErr = NULL;
    SecKeyAlgorithm algo = kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256;
    bool ok = SecKeyVerifySignature(_publicKey,
                                    algo,
                                    (__bridge CFDataRef)digest,
                                    (__bridge CFDataRef)signature,
                                    &secErr);
    if (!ok) {
        if (secErr) {
            CFRelease(secErr);
        }
        return [[NSError alloc] initWithDomain:iTermSignatureVerifierErrorDomain
                                          code:iTermSignatureVerifierErrorCodeSignatureDoesNotMatchError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"RSA signature does not match. Data does not match signature or wrong public key." }];
    }

    return nil;
}

+ (NSData *)derKeyDataFromPEMString:(NSString *)pemString {
    NSString *header = @"-----BEGIN PUBLIC KEY-----";
    NSString *footer = @"-----END PUBLIC KEY-----";
    NSString *keyString = pemString;

    if ([pemString containsString:header] &&
        [pemString containsString:footer]) {
        NSRange start = [pemString rangeOfString:header];
        NSRange end = [pemString rangeOfString:footer];
        NSUInteger loc = NSMaxRange(start);
        NSUInteger len = end.location - loc;
        keyString = [pemString substringWithRange:NSMakeRange(loc, len)];
    }

    keyString = [keyString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return [[NSData alloc] initWithBase64EncodedString:keyString
                                              options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

@end
