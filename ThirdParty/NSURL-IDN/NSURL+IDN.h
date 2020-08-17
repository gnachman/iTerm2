//
// NSURL+IDN.h
//
// Created by Jorge Bernal on 4/8/11.
// Adapted from OmniNetworking framework
//
// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

@interface NSURL (IDN)
+ (NSString *)IDNEncodedHostname:(NSString *)aHostname;
+ (NSString *)IDNDecodedHostname:(NSString *)anIDNHostname;
+ (NSString *)IDNEncodedURL:(NSString *)aURL;
+ (NSString *)IDNDecodedURL:(NSString *)anIDNURL;
@end
