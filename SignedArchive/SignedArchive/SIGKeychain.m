//
//  SIGKeychain.m
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGKeychain.h"

@implementation SIGKeychain

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

+ (NSString *)path {
    NSString *const keychainsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains"];
    NSString *const keychainName = @"login";
    NSString *const fullPath = [keychainsDirectory stringByAppendingPathComponent:keychainName];
    return fullPath;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        OSErr err = SecKeychainOpen([SIGKeychain.path UTF8String],
                                    &_secKeychain);
        if (err != noErr) {
            NSLog(@"Unable to open keychain: %d", err);
            return nil;
        }
        
        err = SecKeychainCopyDefault(&_secKeychain);
        if (err != noErr) {
            NSLog(@"Unable to copy default keychain: %d", err);
            return nil;
        }
    }
    
    return self;
}

- (void)dealloc {
    if (_secKeychain) {
        CFRelease(_secKeychain);
    }
}

@end
