//
//  main.c
//  sign
//
//  Created by George Nachman on 7/28/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SIGArchiveBuilder.h"
#import "SIGArchiveReader.h"
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

NSURL *TemporaryURLOfExtractedUnverifiedPayload(NSURL *archiveURL) {
    SIGArchiveReader *reader;
    reader = [[SIGArchiveReader alloc] initWithURL:archiveURL];
    if (!reader) {
        return nil;
    }

    NSError *error;
    [reader load:&error];
    if (error) {
        return nil;
    }

    NSInputStream *input = [reader payloadInputStream:&error];
    if (error || !input) {
        return nil;
    }


}

int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: resign filename.in identity filename.out\n");
        return -1;
    }

    @autoreleasepool {
        NSURL *oldArchiveURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *payloadURL = TemporaryURLOfExtractedUnverifiedPayload(oldArchiveURL);
        if (!payloadURL) {
            fprintf(stderr, "Could not extract from %s\n", argv[1]);
            return -1;
        }
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
