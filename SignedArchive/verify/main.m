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
#import "SIGError.h"

static NSError *Verify(NSString *path) {
    SIGArchiveVerifier *verifier = [[SIGArchiveVerifier alloc] initWithURL:[NSURL fileURLWithPath:path]];
    __block BOOL result;
    __block NSError *errorResult = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [verifier verifyWithCompletion:^(BOOL ok, NSError *error) {
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
        if (argc < 2) {
            fprintf(stderr, "Usage: verify file [file...]\n");
            return 1;
        }
        int errors = 0;
        for (int i = 1; i < argc; i++) {
            NSError *error = Verify([NSString stringWithUTF8String:argv[i]]);
            if (error) {
                errors++;
                printf("%s: %s\n", argv[i], error.localizedDescription.UTF8String);
            } else {
                printf("%s: %s\n", argv[i], "ok");
            }
        }
        return errors > 0;
    }
}
