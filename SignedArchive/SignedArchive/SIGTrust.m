//
//  SIGTrust.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGTrust.h"

#import "SIGCertificate.h"
#import "SIGError.h"
#import "SIGPolicy.h"

@implementation SIGTrust

- (instancetype)initWithCertificates:(NSArray<SIGCertificate *> *)certificates
                            policies:(NSArray<id<SIGPolicy>> *)policies
                               error:(out NSError * _Nullable __autoreleasing *)error {
    self = [super init];
    if (self) {
        _certificates = [certificates copy];
        _policies = [policies copy];

        NSMutableArray *secCertificates = [NSMutableArray array];
        for (SIGCertificate *certificate in certificates) {
            [secCertificates addObject:(__bridge id)certificate.secCertificate];
        }

        NSMutableArray *secPolicies = [NSMutableArray array];
        for (id<SIGPolicy> policy in policies) {
            [secPolicies addObject:(__bridge id)[policy secPolicy]];
        }

        OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)secCertificates,
                                                         (__bridge CFTypeRef)secPolicies,
                                                         &_secTrust);
        if (status != noErr) {
            if (error) {
                NSString *message = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);
                *error = [SIGError errorWithCode:SIGErrorCodeTrust
                                          detail:message];
            }
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_secTrust) {
        CFRelease(_secTrust);
    }
}

- (void)evaluateWithCompletion:(void (^)(BOOL, NSError *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL trusted;
        NSError *error = nil;
        trusted = [self evaluateTrust:&error];
        completion(trusted, error);
    });
}

#pragma mark - APIs

- (BOOL)evaluateTrust:(out NSError **)error {
    CFErrorRef secError = NULL;
    const BOOL trusted = SecTrustEvaluateWithError(self->_secTrust,
                                                   &secError);
    if (secError && error) {
        *error = [SIGError errorWrapping:(__bridge NSError *)secError
                                    code:SIGErrorCodeTrust
                                  detail:@"Failed to evaluate certificate chain"];
    }
    return trusted;
}

@end
