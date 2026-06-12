//
//  iTermSignatureVerifier.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, iTermSignatureVerifierErrorCode) {
    iTermSignatureVerifierErrorCodeBadPublicKeyError,
    iTermSignatureVerifierErrorCodeBase64Error,
    iTermSignatureVerifierErrorCodeFileNotFound,
    iTermSignatureVerifierErrorCodeReadError,
    iTermSignatureVerifierErrorCodeInternalError,
    iTermSignatureVerifierErrorCodeSignatureVerificationFailedError,
    iTermSignatureVerifierErrorCodeSignatureDoesNotMatchError
};

// Usage Guide
// -----------
// First, create a key pair. Do this once. Use a 4096 bit key because this doesn't have to be fast
// but the signatures might need to be validated for a long time. NIST suggests at least 2048 bits
// for RSA signatures: https://csrc.nist.gov/publications/detail/sp/800-131a/rev-1/final
//    openssl genrsa -des3 -out rsa_priv.pem 4096
//    openssl rsa -in rsa_priv.pem -outform PEM -pubout -out rsa_pub.pem
//
// To create a base-64 encoded signature:
//    openssl dgst -sha256 -sign rsa_priv.pem $FILENAME_TO_SIGN | openssl enc -base64 > $BASE64_SIGNATURE_FILENAME
//
// To verify (same thing this class does):
//    openssl base64 -d -in $BASE64_SIGNATURE_FILENAME -out /tmp/sig.bin
//    openssl dgst -sha256 -verify rsa_pub.pem -signature /tmp/sig.bin $FILENAME_TO_VERIFY
//
// To verify in code:
// NSError *error = [iTermSignatureVerifier validateFileURL:[NSURL fileURLWithPath:@"/path/to/file/to/validate"
//                                                            withEncodedSignature:@"base64 signature here"
//                                                                       publicKey"@"-----BEGIN PUBLIC KEY----\n..."];
// if (error) {
//   NSLog(@"Validation failed: %@", error.localizedDescription);
// } else {
//   NSLog(@"lgtm");
// }
@interface iTermSignatureVerifier : NSObject

- (instancetype)init NS_UNAVAILABLE;

// Checks if a file matches an RSA signature and public key. Uses SHA-256 for the digest.
//
// url: URL of file to validate
// encodedSignature: base64-encoded signature
// encodedPublicKey: PEM-encoded public key (starts with "-----BEGIN PUBLIC KEY-----")
//
// Returns: nil on success or an error if the file could not be validated.
+ (NSError *)validateFileURL:(NSURL *)url
        withEncodedSignature:(NSString *)encodedSignature
                   publicKey:(NSString *)encodedPublicKey;

@end
