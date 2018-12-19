//
//  main.m
//  sign
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SIGArchiveBuilder.h"
#import "SIGCertificate.h"
#import "SIGIdentity.h"
#import <stdio.h>

SIGIdentity *FindSigningIdentity(NSString *query) {
    for (SIGIdentity *identity in [SIGIdentity allSigningIdentities]) {
        if ([identity.signingCertificate.longDescription localizedCaseInsensitiveContainsString:query]) {
            printf("Using identity %s\n", identity.signingCertificate.longDescription.UTF8String);
            return identity;
        }
    }
    return nil;
}

int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: sign filename.in identity filename.out\n");
        return -1;
    }
    
    @autoreleasepool {
        NSURL *payloadURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        SIGIdentity *identity = FindSigningIdentity([NSString stringWithUTF8String:argv[2]]);
        if (!identity) {
            fprintf(stderr, "No identity found\n");
            return -1;
        }
        SIGArchiveBuilder *builder = [[SIGArchiveBuilder alloc] initWithPayloadFileURL:payloadURL
                                                                              identity:identity];
        
        NSError *error = nil;
        NSURL *outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]];
        const BOOL ok = [builder writeToURL:outputURL error:&error];
        if (!ok) {
            fprintf(stderr, "Signing error: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
    return 0;
}
