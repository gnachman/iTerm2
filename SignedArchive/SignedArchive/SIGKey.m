//
//  SIGKey.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGKey.h"

@implementation SIGKey

- (instancetype)initWithSecKey:(SecKeyRef)secKey {
    self = [super init];
    if (self) {
        CFRetain(secKey);
        _secKey = secKey;
    }
    return self;
}

- (void)dealloc {
    if (_secKey) {
        CFRelease(_secKey);
    }
}

@end
