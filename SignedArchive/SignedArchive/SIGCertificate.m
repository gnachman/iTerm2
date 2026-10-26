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
    if (!secCertificate) {
        return nil;
    }
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
    // initWithData: returns nil without a certificate when the data is malformed, and
    // CFRelease(NULL) crashes.
    if (_secCertificate) {
        CFRelease(_secCertificate);
    }
}

- (SIGKey *)publicKey {
    if (_publicKey) {
        return _publicKey;
    }

    SecKeyRef key = SecCertificateCopyKey(_secCertificate);
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
    CFStringRef value = NULL;
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
    if (error) {
        CFRelease(error);
        return nil;
    }
    if (value == NULL) {
        return nil;
    }
    return value;
}

- (NSDate *)expirationDate {
    // The validity period's Not After date. Its value is a CFNumber of seconds since the
    // reference date.
    NSArray *keys = @[ (__bridge id)kSecOIDX509V1ValidityNotAfter ];
    NSDictionary *values = (__bridge_transfer NSDictionary *)SecCertificateCopyValues(_secCertificate,
                                                                                    (__bridge CFArrayRef)keys,
                                                                                    NULL);
    NSDictionary *property = values[(__bridge id)kSecOIDX509V1ValidityNotAfter];
    if (![property isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id value = property[(__bridge id)kSecPropertyKeyValue];
    if ([value isKindOfClass:[NSDate class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSDate dateWithTimeIntervalSinceReferenceDate:[value doubleValue]];
    }
    return nil;
}

- (NSData *)serialNumber {
    CFErrorRef error = NULL;
    NSData *value = (__bridge_transfer NSData *)SecCertificateCopySerialNumberData(_secCertificate,
                                                                                   &error);
    if (error) {
        CFRelease(error);
        return nil;
    }
    if (value == NULL) {
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

    CFDataRef subjectContent = SecCertificateCopyNormalizedSubjectSequence(secCertificate);
    if (!subjectContent) {
        return NO;
    }
    const BOOL result = CFEqual(subjectContent, name);
    CFRelease(subjectContent);
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
    BOOL found = NO;
    for (NSInteger i = 0; i < CFArrayGetCount(array); i++) {
        if ([self certificateInArray:array atIndex:i hasName:name]) {
            found = YES;
            break;
        }
    }
    CFRelease(array);
    return found;
}

// Returns a +1 reference that the caller must release, or NULL.
+ (SecCertificateRef)copySecCertificateWithName:(CFDataRef)name {
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
    SecCertificateRef found = NULL;
    for (NSInteger i = 0; i < CFArrayGetCount(array); i++) {
        if ([SIGCertificate certificateInArray:array atIndex:i hasName:name]) {
            found = (SecCertificateRef)CFArrayGetValueAtIndex(array, i);
            CFRetain(found);
            break;
        }
    }
    CFRelease(array);
    return found;
}

- (SIGCertificate *)issuer {
    if (!_secCertificate) {
        return nil;
    }
    CFDataRef issuerName = SecCertificateCopyNormalizedIssuerSequence(_secCertificate);
    if (!issuerName) {
        return nil;
    }
    SecCertificateRef secCertificate = [SIGCertificate copySecCertificateWithName:issuerName];
    CFRelease(issuerName);
    if (secCertificate == NULL) {
        return nil;
    }
    SIGCertificate *issuer = [[SIGCertificate alloc] initWithSecCertificate:secCertificate];
    CFRelease(secCertificate);
    return issuer;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[SIGCertificate class]]) {
        return NO;
    }
    SIGCertificate *other = object;
    return [self.data isEqual:other.data];
}

@end
