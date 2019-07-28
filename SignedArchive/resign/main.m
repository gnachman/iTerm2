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

NSURL *CreateTemporaryURL(NSURL *eventualDestinationURL) {
    NSURL *destinationURL = eventualDestinationURL;

    NSError *error = nil;
    NSURL *temporaryDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSItemReplacementDirectory
                                                                          inDomain:NSUserDomainMask
                                                                 appropriateForURL:destinationURL
                                                                            create:YES
                                                                             error:&error];
    if (!temporaryDirectoryURL || error) {
        return nil;
    }

    NSString *temporaryFilename = [[NSProcessInfo processInfo] globallyUniqueString];
    return [temporaryDirectoryURL URLByAppendingPathComponent:temporaryFilename];
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
        fprintf(stderr, "Failed to load %s: %s\n", archiveURL.path.UTF8String, error.localizedDescription.UTF8String);
        return nil;
    }

    NSInputStream *readStream = [reader payloadInputStream:&error];
    if (error || !readStream) {
        fprintf(stderr, "Could not realize input stream from %s: %s\n", archiveURL.path.UTF8String, error.localizedDescription.UTF8String);
        return nil;
    }
    [readStream open];

    NSURL *url = CreateTemporaryURL([NSURL fileURLWithPath:NSTemporaryDirectory()]);
    if (!url) {
        fprintf(stderr, "Could not create temporary file in %s\n", NSTemporaryDirectory().UTF8String);
        return nil;
    }

    NSOutputStream *writeStream = [[NSOutputStream alloc] initWithURL:url append:NO];
    if (!writeStream) {
        fprintf(stderr, "Could not create output stream to write to %s\n", url.path.UTF8String);
        return nil;
    }
    [writeStream open];

    NSInteger numberOfBytesCopied = 0;
    while ([readStream hasBytesAvailable]) {
        uint8_t buffer[4096];
        const NSInteger numberOfBytesRead = [readStream read:buffer maxLength:sizeof(buffer)];
        if (numberOfBytesRead == 0) {
            break;
        }
        if (numberOfBytesRead < 0) {
            fprintf(stderr, "Error %s reading from %s\n", readStream.streamError.localizedDescription.UTF8String, archiveURL.path.UTF8String);
            return nil;
        }

        const NSInteger numberOfBytesWritten = [writeStream write:buffer maxLength:numberOfBytesRead];
        if (numberOfBytesWritten != numberOfBytesRead) {
            fprintf(stderr, "Error %s while writing to %s\n", writeStream.streamError.localizedDescription.UTF8String, url.path.UTF8String);
            return nil;
        }

        numberOfBytesCopied += numberOfBytesWritten;
    }
    [writeStream close];

    return url;
}


int main(int argc, const char * argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: resign filename.in identity filename.out\n");
        return -1;
    }

    @autoreleasepool {
        NSURL *oldArchiveURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *payloadURL = TemporaryURLOfExtractedUnverifiedPayload(oldArchiveURL);
        do {
            if (!payloadURL) {
                fprintf(stderr, "Could not extract from %s\n", argv[1]);
                break;
            }
            SIGIdentity *identity = FindSigningIdentity([NSString stringWithUTF8String:argv[2]]);
            if (!identity) {
                fprintf(stderr, "No identity found\n");
                break;
            }
            SIGArchiveBuilder *builder = [[SIGArchiveBuilder alloc] initWithPayloadFileURL:payloadURL
                                                                                  identity:identity];

            NSError *error = nil;
            NSURL *outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]];
            const BOOL ok = [builder writeToURL:outputURL error:&error];
            if (!ok) {
                fprintf(stderr, "Signing error: %s\n", error.localizedDescription.UTF8String);
                break;
            }
        } while (0);

        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtURL:payloadURL error:&error];
        if (error) {
            fprintf(stderr, "While deleting temp file %s: %s\n", payloadURL.path.UTF8String, error.localizedDescription.UTF8String);
        }
    }
    return 0;
}
