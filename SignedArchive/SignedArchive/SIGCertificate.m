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

- (SIGKey *)publicKey {
    if (_publicKey) {
        return _publicKey;
    }

    SecKeyRef key;
    if (@available(macOS 10.14, *)) {
        key = SecCertificateCopyKey(_secCertificate);
    } else {
        const OSStatus status = SecCertificateCopyPublicKey(_secCertificate, &key);
        if (status != noErr) {
            return nil;
        }
    }
    if (!key) {
        return nil;
    }

    _publicKey = [[SIGKey alloc] initWithSecKey:key];

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
    if (@available(macOS 10.13, *)) {
        value = (__bridge_transfer NSData *)SecCertificateCopySerialNumberData(_secCertificate,
                                                                               &error);
    } else {
        value = (__bridge_transfer NSData *)SecCertificateCopySerialNumber(_secCertificate,
                                                                           &error);
    }
    if (value == NULL || error != NULL) {
        return nil;
    }
    return value;
}

@end
