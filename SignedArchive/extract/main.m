//
//  main.m
//  extract
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <readpassphrase.h>
#import <stdio.h>
#import "SIGArchiveReader.h"
#import "SIGArchiveVerifier.h"
#import "SIGError.h"
#import "extract-Swift.h"

// An encrypted archive is unsigned, so there is nothing to verify: the passphrase is the check.
// The plaintext is written readable only by its owner, since it may hold passwords.
static NSError *Decrypt(SIGArchiveReader *reader, NSURL *destinationURL) {
    char buffer[1024];
    if (!readpassphrase("Passphrase: ", buffer, sizeof(buffer), RPP_ECHO_OFF)) {
        return [SIGError errorWithCode:SIGErrorCodeUnknown detail:@"Couldn't read the passphrase."];
    }
    NSString *passphrase = [NSString stringWithUTF8String:buffer];
    memset_s(buffer, sizeof(buffer), 0, sizeof(buffer));
    if (!passphrase) {
        return [SIGError errorWithCode:SIGErrorCodeUnknown detail:@"The passphrase isn't valid UTF-8."];
    }
    NSError *error = nil;
    NSData *plaintext = [reader decryptedPayloadWithPassphrase:passphrase
                                                        cipher:[[SIGArchiveAESGCMCipher alloc] init]
                                                         error:&error];
    if (!plaintext) {
        return error;
    }
    if (![[NSFileManager defaultManager] createFileAtPath:destinationURL.path
                                                 contents:plaintext
                                               attributes:@{ NSFilePosixPermissions: @0600 }]) {
        return [SIGError errorWithCode:SIGErrorCodeIOWrite detail:@"Couldn't write the destination file."];
    }
    return nil;
}

static NSError *Extract(NSString *source, NSString *destination) {
    NSURL *destinationURL = [NSURL fileURLWithPath:destination];
    if (!destinationURL) {
        return [SIGError errorWithCode:SIGErrorCodeIOWrite detail:@"Destination filename malformed."];
    }
    SIGArchiveReader *reader = [[SIGArchiveReader alloc] initWithURL:[NSURL fileURLWithPath:source]];
    NSError *loadError = nil;
    if ([reader load:&loadError] && [reader isEncrypted]) {
        return Decrypt(reader, destinationURL);
    }
    // Anything else, including a file that won't load, goes through the verifier, which
    // reports the problem.
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
            fprintf(stderr, "Usage: extract file.in file.out\n"
                            "Verifies a signed archive and writes its payload. For an encrypted\n"
                            "archive, asks for the passphrase and writes the decrypted payload.\n");
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

