//
//  SIGArchiveEncryption.h
//  SignedArchive
//
//  Created by George Nachman on 10/12/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// An encrypted archive's payload chunk holds an AES-256-GCM sealed box (12-byte nonce, then
// ciphertext, then 16-byte tag). The key comes from PBKDF2-HMAC-SHA256 over the UTF-8 encoding of
// the passphrase in Unicode Normalization Form C, with the iteration count and salt recorded in the
// metadata chunk. The additional authenticated data is
// every byte of the file that precedes the payload, so the header, metadata (including the KDF
// parameters), and the payload chunk's tag and length are all bound to the ciphertext.
//
// An encrypted archive is never signed: SIGArchiveVerifier refuses encrypted archives, so nothing
// could check such a signature. Its integrity comes from GCM alone.

extern NSString *const SIGArchiveEncryptionAES256GCM;
extern NSString *const SIGArchiveKDFPBKDF2SHA256;

extern const NSUInteger SIGArchiveEncryptionKeyLength;
extern const NSUInteger SIGArchiveEncryptionSaltLength;
// Nonce plus tag.
extern const NSUInteger SIGArchiveEncryptionOverhead;
extern const unsigned int SIGArchiveEncryptionDefaultIterations;
// Readers reject files that claim fewer iterations than this, so a forged file can't downgrade
// the work factor.
extern const unsigned int SIGArchiveEncryptionMinimumIterations;

// AES-GCM has no public Objective-C API, so the app supplies one (CryptoKit, from Swift).
@protocol SIGAuthenticatedCipher<NSObject>

// Returns nonce || ciphertext || tag.
- (nullable NSData *)sealPlaintext:(NSData *)plaintext
                               key:(NSData *)key
                               aad:(NSData *)aad
                             error:(out NSError **)error;

// Takes nonce || ciphertext || tag. Returns nil if authentication fails.
- (nullable NSData *)openSealedBox:(NSData *)sealedBox
                               key:(NSData *)key
                               aad:(NSData *)aad
                             error:(out NSError **)error;

@end

@interface SIGArchivePassphraseEncryption : NSObject

@property (nonatomic, readonly) id<SIGAuthenticatedCipher> cipher;
@property (nonatomic, readonly) unsigned int iterations;
@property (nonatomic, readonly) NSData *salt;

// For writing. Generates a random salt.
- (nullable instancetype)initWithPassphrase:(NSString *)passphrase
                                     cipher:(id<SIGAuthenticatedCipher>)cipher
                                 iterations:(unsigned int)iterations;

// For reading. Validates the parameters found in the metadata.
- (nullable instancetype)initWithPassphrase:(NSString *)passphrase
                                     cipher:(id<SIGAuthenticatedCipher>)cipher
                                   metadata:(NSDictionary<NSString *, NSString *> *)metadata
                          minimumIterations:(unsigned int)minimumIterations
                                      error:(out NSError **)error;

- (instancetype)init NS_UNAVAILABLE;

// key=value pairs to add to the metadata chunk.
- (NSDictionary<NSString *, NSString *> *)metadataEntries;

- (nullable NSData *)derivedKey:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
