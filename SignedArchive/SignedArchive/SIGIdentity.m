//
//  SIGIdentity.m
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGIdentity.h"

#import "SIGCertificate.h"
#import "SIGKey.h"
#import "SIGKeychain.h"

@implementation SIGIdentity {
    SIGCertificate *_signingCertificate;
}

+ (NSDictionary *)queryForSigningIdentities {
    NSDictionary *dict = @{ (__bridge id)kSecClass: (__bridge id)kSecClassIdentity,
                            (__bridge id)kSecReturnRef: (__bridge id)kCFBooleanTrue,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll };
    return dict;
}

+ (NSArray<SIGIdentity *> *)allSigningIdentities {
    SIGKeychain *keychain = [SIGKeychain sharedInstance];
    if (keychain == nil) {
        return @[];
    }

    NSDictionary *query = [self queryForSigningIdentities];

    CFTypeRef result = NULL;
    OSErr err = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (err != noErr) {
        NSLog(@"Unable to create keychain search: %d", err);
        return @[];
    }

    CFArrayRef array = (CFArrayRef)result;
    NSMutableArray<SIGIdentity *> *identities = [NSMutableArray array];
    for (NSInteger i = 0; i < CFArrayGetCount(array); i++) {
        SecIdentityRef secIdentity = (SecIdentityRef)CFArrayGetValueAtIndex(array, i);
        SIGIdentity *identity = [[SIGIdentity alloc] initWithSecIdentity:secIdentity];
        if (!identity) {
            continue;
        }
        [identities addObject:identity];
    }
    return identities;
}

- (instancetype)initWithSecIdentity:(SecIdentityRef)secIdentity {
    if (!secIdentity) {
        return nil;
    }

    self = [super init];
    if (self) {
        _secIdentity = secIdentity;
    }
    return self;
}

- (void)dealloc {
    if (_secIdentity) {
        CFRelease(_secIdentity);
    }
}

- (SIGKey *)privateKey {
    SecKeyRef privateKey;
    OSStatus err = SecIdentityCopyPrivateKey(_secIdentity,
                                             &privateKey);
    if (err != noErr) {
        return nil;
    }
    
    return [[SIGKey alloc] initWithSecKey:privateKey];
}

- (SIGCertificate *)signingCertificate {
    if (_signingCertificate != nil) {
        return _signingCertificate;
    }

    SecCertificateRef secCertificate;
    const OSStatus err = SecIdentityCopyCertificate(_secIdentity, &secCertificate);
    if (err != noErr) {
        return nil;
    }

    _signingCertificate = [[SIGCertificate alloc] initWithSecCertificate:secCertificate];
    return _signingCertificate;
}

@end
