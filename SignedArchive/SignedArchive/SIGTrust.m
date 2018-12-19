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
        if (@available(macOS 10.14, *)) {
            trusted = [self evaluateTrust:&error];
        } else {
            trusted = [self evaluateTrustPreMojave:&error];
        }
        completion(trusted, error);
    });
}

#pragma mark - APIs

- (BOOL)evaluateTrust:(out NSError **)error NS_AVAILABLE_MAC(10_14) {
    CFErrorRef secError = NULL;
    const BOOL trusted = SecTrustEvaluateWithError(self->_secTrust,
                                                   &secError);
    if (secError) {
        *error = [SIGError errorWrapping:(__bridge NSError *)secError
                                    code:SIGErrorCodeTrust
                                  detail:@"Failed to evaluate certificate chain"];
    }
    return trusted;
}

- (BOOL)resultIsTrustedPreMojave:(SecTrustResultType)trustResult
                           error:(out NSError **)error NS_DEPRECATED_MAC(10_0, 10_14) {
    switch (trustResult) {
        case kSecTrustResultDeny:  // user-configured deny
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeTrustUserDeny];
            }
            break;
        case kSecTrustResultOtherError:  // a failure other than that of trust evaluation
        case kSecTrustResultInvalid:  // invalid setting or result
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeTrustMisconfiguration];
            }
            break;
        case kSecTrustResultFatalTrustFailure:  // trust failure which cannot be overridden by the user
        case kSecTrustResultRecoverableTrustFailure:  // a trust policy failure which can be overridden by the user
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeTrustFailed];
            }
            break;

        case kSecTrustResultProceed:  // you may proceed
        case kSecTrustResultUnspecified:  // the certificate is implicitly trusted, but user intent was not explicitly specified
            if (error) {
                *error = nil;
            }
            return YES;
            break;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case kSecTrustResultConfirm:
#pragma clang diagnostic pop
            assert(NO);
            break;
    }
    return NO;
}

- (BOOL)evaluateTrustPreMojave:(out NSError **)error NS_DEPRECATED_MAC(10_0, 10_14) {
    SecTrustResultType result;
    const OSStatus status = SecTrustEvaluate(self->_secTrust, &result);
    if (status != noErr) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeTrustFailed];
        }
        return NO;
    } else {
        return [self resultIsTrustedPreMojave:result error:error];
    }
}

@end
