//
//  SIGPolicy.m
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGPolicy.h"

@implementation SIGX509Policy {
    SecPolicyRef _policy;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _policy = SecPolicyCreateBasicX509();
        if (!_policy) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_policy) {
        CFRelease(_policy);
    }
}

- (SecPolicyRef)secPolicy {
    return _policy;
}

@end

@implementation SIGCRLPolicy {
    SecPolicyRef _policy;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        const CFOptionFlags flags = (kSecRevocationCRLMethod);
        _policy = SecPolicyCreateRevocation(flags);
        if (!_policy) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_policy) {
        CFRelease(_policy);
    }
}

- (SecPolicyRef)secPolicy {
    return _policy;
}

@end
