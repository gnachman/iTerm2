//
//  SIGArchiveEncryption.m
//  SignedArchive
//
//  Created by George Nachman on 10/12/26.
//

#import "SIGArchiveEncryption.h"

#import "SIGArchiveCommon.h"
#import "SIGError.h"

#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

NSString *const SIGArchiveEncryptionAES256GCM = @"aes-256-gcm";
NSString *const SIGArchiveKDFPBKDF2SHA256 = @"pbkdf2-sha256";

const NSUInteger SIGArchiveEncryptionKeyLength = 32;
const NSUInteger SIGArchiveEncryptionSaltLength = 16;
const NSUInteger SIGArchiveEncryptionOverhead = 12 + 16;
const unsigned int SIGArchiveEncryptionDefaultIterations = 600000;
const unsigned int SIGArchiveEncryptionMinimumIterations = 100000;

// Caps the work a crafted file can make us do.
static const unsigned int SIGArchiveEncryptionMaximumIterations = 10000000;

@implementation SIGArchivePassphraseEncryption {
    NSString *_passphrase;
}

- (instancetype)initWithPassphrase:(NSString *)passphrase
                            cipher:(id<SIGAuthenticatedCipher>)cipher
                        iterations:(unsigned int)iterations {
    NSMutableData *salt = [NSMutableData dataWithLength:SIGArchiveEncryptionSaltLength];
    if (SecRandomCopyBytes(kSecRandomDefault, salt.length, salt.mutableBytes) != errSecSuccess) {
        return nil;
    }
    return [self initWithPassphrase:passphrase cipher:cipher iterations:iterations salt:salt];
}

- (instancetype)initWithPassphrase:(NSString *)passphrase
                            cipher:(id<SIGAuthenticatedCipher>)cipher
                          metadata:(NSDictionary<NSString *, NSString *> *)metadata
                 minimumIterations:(unsigned int)minimumIterations
                             error:(out NSError **)error {
    if (![metadata[SIGArchiveMetadataKeyEncryption] isEqualToString:SIGArchiveEncryptionAES256GCM] ||
        ![metadata[SIGArchiveMetadataKeyKDF] isEqualToString:SIGArchiveKDFPBKDF2SHA256]) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnsupportedAlgorithm];
        }
        return nil;
    }
    NSString *iterationsString = metadata[SIGArchiveMetadataKeyKDFIterations];
    NSScanner *scanner = [NSScanner scannerWithString:iterationsString ?: @""];
    unsigned long long iterations = 0;
    const BOOL scanned = ([scanner scanUnsignedLongLong:&iterations] && scanner.isAtEnd);
    NSData *salt = nil;
    NSString *saltString = metadata[SIGArchiveMetadataKeyKDFSalt];
    if (saltString) {
        salt = [[NSData alloc] initWithBase64EncodedString:saltString options:0];
    }
    if (scanned && iterations > SIGArchiveEncryptionMaximumIterations) {
        // Not necessarily damage: a newer version may use more iterations than this one allows.
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnsupportedAlgorithm
                                      detail:[NSString stringWithFormat:@"The archive uses %llu key derivation iterations, more than the maximum of %u",
                                              iterations, SIGArchiveEncryptionMaximumIterations]];
        }
        return nil;
    }
    if (!scanned ||
        iterations < minimumIterations ||
        salt.length != SIGArchiveEncryptionSaltLength) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeBadEncryptionParameters];
        }
        return nil;
    }
    return [self initWithPassphrase:passphrase
                             cipher:cipher
                         iterations:(unsigned int)iterations
                               salt:salt];
}

- (instancetype)initWithPassphrase:(NSString *)passphrase
                            cipher:(id<SIGAuthenticatedCipher>)cipher
                        iterations:(unsigned int)iterations
                              salt:(NSData *)salt {
    self = [super init];
    if (self) {
        _passphrase = [passphrase copy];
        _cipher = cipher;
        _iterations = iterations;
        _salt = [salt copy];
    }
    return self;
}

- (NSDictionary<NSString *, NSString *> *)metadataEntries {
    return @{
        SIGArchiveMetadataKeyEncryption: SIGArchiveEncryptionAES256GCM,
        SIGArchiveMetadataKeyKDF: SIGArchiveKDFPBKDF2SHA256,
        SIGArchiveMetadataKeyKDFIterations: [@(_iterations) stringValue],
        SIGArchiveMetadataKeyKDFSalt: [_salt base64EncodedStringWithOptions:0]
    };
}

- (NSData *)derivedKey:(out NSError **)error {
    // Normalize so the same passphrase typed (NFC) or pasted from a filename (NFD) gives the same key.
    NSData *passphraseData = [_passphrase.precomposedStringWithCanonicalMapping dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *key = [NSMutableData dataWithLength:SIGArchiveEncryptionKeyLength];
    const int status = CCKeyDerivationPBKDF(kCCPBKDF2,
                                            passphraseData.bytes,
                                            passphraseData.length,
                                            _salt.bytes,
                                            _salt.length,
                                            kCCPRFHmacAlgSHA256,
                                            _iterations,
                                            key.mutableBytes,
                                            key.length);
    if (status != kCCSuccess) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeAlgorithmCreationFailed
                                      detail:[NSString stringWithFormat:@"Key derivation failed with status %d", status]];
        }
        return nil;
    }
    return key;
}

@end
