//
//  SIGCertificate.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGCertificate.h"

#import "SIGKey.h"
#import "SIGTrust.h"

@implementation SIGCertificate {
    SIGKey *_publicKey;
}

- (instancetype)initWithSecCertificate:(SecCertificateRef)secCertificate {
    self = [super init];
    if (self) {
        _secCertificate = secCertificate;
        CFRetain(secCertificate);
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        _secCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
        if (!_secCertificate) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    CFRelease(_secCertificate);
}

- (SIGKey *)publicKey {
    if (_publicKey) {
        return _publicKey;
    }

    SecKeyRef key;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_14
    if (@available(macOS 10.14, *)) {
        key = SecCertificateCopyKey(_secCertificate);
    }
    else {
        const OSStatus status = SecCertificateCopyPublicKey(_secCertificate, &key);
        if (status != noErr) {
            return nil;
        }
    }
#else
    key = SecCertificateCopyKey(_secCertificate);
#endif
    if (!key) {
        return nil;
    }

    _publicKey = [[SIGKey alloc] initWithSecKey:key];
    CFRelease(key);

    return _publicKey;
}

- (NSData *)data {
    return (__bridge_transfer NSData *)SecCertificateCopyData(_secCertificate);
}

- (NSString *)name {
    CFStringRef value;
    const OSStatus status = SecCertificateCopyCommonName(_secCertificate,
                                                         &value);
    NSString *string = (__bridge_transfer NSString *)value;
    if (string == NULL || status != noErr) {
        return nil;
    }
    return string;
}

- (NSString *)longDescription {
    CFErrorRef error = NULL;
    NSString *value = (__bridge_transfer NSString *)SecCertificateCopyLongDescription(NULL,
                                                                                      _secCertificate,
                                                                                      &error);
    if (value == NULL || error != NULL) {
        return nil;
    }
    return value;
}

- (NSData *)serialNumber {
    CFErrorRef error = NULL;
    NSData *value;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_13
    if (@available(macOS 10.13, *)) {
        value = (__bridge_transfer NSData *)SecCertificateCopySerialNumberData(_secCertificate,
                                                                               &error);
    } else {
        value = (__bridge_transfer NSData *)SecCertificateCopySerialNumber(_secCertificate,
                                                                           &error);
    }
#else
    value = (__bridge_transfer NSData *)SecCertificateCopySerialNumberData(_secCertificate,
                                                                           &error);
#endif
    if (value == NULL || error != NULL) {
        return nil;
    }
    return value;
}

+ (NSDictionary *)queryForCertWithName:(CFDataRef)name {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassCertificate,
              (__bridge id)kSecAttrSubject: (__bridge NSData *)name,
              (__bridge id)kSecReturnRef: (__bridge id)kCFBooleanTrue,
              (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll };
}

+ (BOOL)certificateInArray:(CFArrayRef)array atIndex:(NSInteger)i hasName:(CFDataRef)name {
    SecCertificateRef secCertificate = (SecCertificateRef)CFArrayGetValueAtIndex(array, i);

    CFDataRef subjectContent;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_12_4
    if (@available(macOS 10.12.4, *)) {
        subjectContent = SecCertificateCopyNormalizedSubjectSequence(secCertificate);
    } else {
        subjectContent = SecCertificateCopyNormalizedSubjectContent(secCertificate, NULL);
    }
#else
    subjectContent = SecCertificateCopyNormalizedSubjectSequence(secCertificate);
#endif

    const BOOL result = CFEqual(subjectContent, name);
    if (subjectContent) {
        CFRelease(subjectContent);
    }
    return result;
}

+ (BOOL)certificateIsRootWithName:(CFDataRef)name {
    CFArrayRef array;
    OSStatus err = SecTrustCopyAnchorCertificates(&array);
    if (err != noErr) {
        NSLog(@"Failed to get root certs: %@",
              (__bridge_transfer NSString *)SecCopyErrorMessageString(err, NULL));
        return NO;
    }
    for (NSInteger i = 0; i < CFArrayGetCount(array); i++) {
        if ([self certificateInArray:array atIndex:i hasName:name]) {
            return YES;
        }
    }
    return NO;
}

+ (SecCertificateRef)secCertificateWithName:(CFDataRef)name {
    if (name == NULL) {
        return NULL;
    }
    NSDictionary *query = [self queryForCertWithName:name];
    CFTypeRef result = NULL;
    OSErr err = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (err != noErr) {
        if (![self certificateIsRootWithName:name]) {
            NSLog(@"Failed to get certificate: %@",
                  (__bridge_transfer NSString *)SecCopyErrorMessageString(err, NULL));
        }
        return nil;
    }

    CFArrayRef array = (CFArrayRef)result;
    for (NSInteger i = 0; i < CFArrayGetCount(array); i++) {
        if ([SIGCertificate certificateInArray:array atIndex:i hasName:name]) {
            return (SecCertificateRef)CFArrayGetValueAtIndex(array, i);
        }
    }

    return NULL;
}

- (SIGCertificate *)issuer {
    if (!_secCertificate) {
        return nil;
    }
    CFDataRef issuerName = SecCertificateCopyNormalizedIssuerSequence(_secCertificate);
    if (!issuerName) {
        return nil;
    }
    SecCertificateRef secCertificate = [SIGCertificate secCertificateWithName:issuerName];
    CFRelease(issuerName);
    if (secCertificate == NULL) {
        return nil;
    }
    return [[SIGCertificate alloc] initWithSecCertificate:secCertificate];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[SIGCertificate class]]) {
        return NO;
    }
    SIGCertificate *other = object;
    return [self.data isEqual:other.data];
}

@end
