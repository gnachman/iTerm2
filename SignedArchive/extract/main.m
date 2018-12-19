//
//  main.m
//  extract
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdio.h>
#import "SIGArchiveVerifier.h"
#import "SIGError.h"

static NSError *Extract(NSString *source, NSString *destination) {
    NSURL *destinationURL = [NSURL fileURLWithPath:destination];
    if (!destinationURL) {
        return [SIGError errorWithCode:SIGErrorCodeIOWrite detail:@"Destination filename malformed."];
    }
    SIGArchiveVerifier *verifier = [[SIGArchiveVerifier alloc] initWithURL:[NSURL fileURLWithPath:source]];
    __block BOOL result;
    __block NSError *errorResult = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [verifier verifyAndWritePayloadToURL:destinationURL completion:^(BOOL ok, NSError *error) {
        result = ok;
        errorResult = error;
        dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
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
        if (argc != 3) {
            fprintf(stderr, "Usage: extract file.in file.out");
            return 1;
        }
        NSError *error = Extract([NSString stringWithUTF8String:argv[1]],
                                 [NSString stringWithUTF8String:argv[2]]);
        if (error) {
            printf("%s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        return 0;
    }
}

