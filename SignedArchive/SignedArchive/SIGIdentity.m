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
#import "SIGPolicy.h"
#import "SIGTrust.h"

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
    NSDictionary *query = [self queryForSigningIdentities];

    CFTypeRef result = NULL;
    OSErr err = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (err != noErr) {
        NSLog(@"Unable to create keychain search: %d", err);
        return @[];
    }

    CFArrayRef array = (CFArrayRef)result;
    NSMutableArray<SIGIdentity *> *identities = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    for (NSInteger i = 0; i < CFArrayGetCount(array); i++) {
        SecIdentityRef secIdentity = (SecIdentityRef)CFArrayGetValueAtIndex(array, i);
        SIGIdentity *identity = [[SIGIdentity alloc] initWithSecIdentity:secIdentity];
        if (!identity) {
            continue;
        }
        NSError *trustError = nil;
        // Don't use the CRL policy because it would need to make a network round-trip.
        SIGTrust *trust = [[SIGTrust alloc] initWithCertificates:@[ identity.signingCertificate ]
                                                        policies:@[ [[SIGX509Policy alloc] init] ]
                                                           error:&trustError];
        if (!trust || trustError) {
            continue;
        }
        dispatch_group_enter(group);
        [trust evaluateWithCompletion:^(BOOL ok, NSError * _Nullable error) {
            if (ok) {
                @synchronized(identities) {
                    [identities addObject:identity];
                }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    @synchronized(identities) {
        return identities;
    }
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
    
    SIGKey *result = [[SIGKey alloc] initWithSecKey:privateKey];
    CFRelease(privateKey);
    return result;
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
