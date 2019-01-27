//
//  main.m
//  verify
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "SIGArchiveVerifier.h"
#import "SIGCertificate.h"
#import "SIGError.h"

static NSString *Details(SIGArchiveVerifier *verifier) {
    NSMutableArray<NSString *> *detailLines = [NSMutableArray array];
    [detailLines addObject:@"    The following certificates were found:"];
    BOOL first = YES;
    for (NSData *data in [verifier.reader signingCertificates:nil]) {
        SIGCertificate *cert = [[SIGCertificate alloc] initWithData:data];
        if (!cert) {
            continue;
        }
        NSString *name = ((cert.name ?: cert.longDescription) ?: @"Unknown");
        NSString *line = [NSString stringWithFormat:@"       Certificate “%@”", name];
        if (first) {
            line = [line stringByAppendingFormat:@" [signing cert]"];
        }

        if (cert.issuer) {
            NSString *name = ((cert.issuer.name ?: cert.issuer.longDescription) ?: @"Unknown");
            line = [line stringByAppendingFormat:@", issued by “%@”", name];
        }
        first = NO;
        [detailLines addObject:line];
    }

    NSError *error;
    NSString *metadata = [verifier.reader metadata:&error];
    if (metadata.length > 0) {
        [detailLines addObject:@"    Metadata:"];
        for (NSString *line in [metadata componentsSeparatedByString:@"\n"]) {
            [detailLines addObject:[@"        " stringByAppendingString:line]];
        }
    }

    [detailLines addObject:[NSString stringWithFormat:@"    Payload length: %@", @(verifier.reader.payloadLength)]];
    return [detailLines componentsJoinedByString:@"\n"];
}

static NSError *Verify(NSString *path, NSString **detailsPtr) {
    SIGArchiveVerifier *verifier = [[SIGArchiveVerifier alloc] initWithURL:[NSURL fileURLWithPath:path]];
    __block BOOL result;
    __block NSError *errorResult = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block NSString *details;
    [verifier verifyWithCompletion:^(BOOL ok, NSError *error) {
        details = Details(verifier);
        result = ok;
        errorResult = error;
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    if (detailsPtr) {
        *detailsPtr = details;
    }
    if (result) {
        return nil;
    }
    if (errorResult) {
        return errorResult;
    }
    return [SIGError errorWithCode:SIGErrorCodeUnknown detail:@"Verification failed for an unknown reason"];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: verify [-v] file [file...]\n");
            return 1;
        }
        int errors = 0;
        int first = 1;
        BOOL verbose = NO;
        if (argc > 1 && !strcmp(argv[1], "-v")) {
            verbose = YES;
            first++;
        }
        for (int i = first; i < argc; i++) {
            NSString *details;
            NSError *error = Verify([NSString stringWithUTF8String:argv[i]],
                                    verbose ? &details : NULL);
            if (error) {
                errors++;
                printf("%s: %s\n", argv[i], error.localizedDescription.UTF8String);
            } else {
                printf("%s: %s\n", argv[i], "ok");
                if (verbose) {
                    printf("%s\n", details.UTF8String);
                }
            }
        }
        return errors > 0;
    }
}
