//
//  main.c
//  sign
//
//  Created by George Nachman on 7/28/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SIGArchiveBuilder.h"
#import "SIGArchiveCommon.h"
#import "SIGArchiveReader.h"
#import "SIGCertificate.h"
#import "SIGIdentity.h"
#import <stdio.h>

typedef enum {
    SIGReSignModeError,
    SIGReSignModeMultiple,
    SIGReSignModeSingle
} SIGReSignMode;

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

static BOOL ReSignExtracted(NSURL *oldArchiveURL,
                            NSString *identityName,
                            NSURL *outputURL,
                            NSURL *payloadURL) {
    if (!payloadURL) {
        fprintf(stderr, "Could not extract from %s\n", oldArchiveURL.path.UTF8String);
        return NO;
    }
    SIGIdentity *identity = FindSigningIdentity(identityName);
    if (!identity) {
        fprintf(stderr, "No identity found\n");
        return NO;
    }
    SIGArchiveBuilder *builder = [[SIGArchiveBuilder alloc] initWithPayloadFileURL:payloadURL
                                                                          identity:identity];

    NSError *error = nil;
    const BOOL ok = [builder writeToURL:outputURL error:&error];
    if (!ok) {
        fprintf(stderr, "Signing error: %s\n", error.localizedDescription.UTF8String);
        return NO;
    }

    return YES;
}

static void DeleteTempFile(NSURL *payloadURL) {
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:payloadURL error:&error];
    if (error) {
        fprintf(stderr, "Warning: While deleting temp file %s: %s\n",
                payloadURL.path.UTF8String, error.localizedDescription.UTF8String);
    }
}

static BOOL ReSign(NSURL *oldArchiveURL,
                   NSString *identityName,
                   NSURL *outputURL) {
    NSURL *payloadURL = TemporaryURLOfExtractedUnverifiedPayload(oldArchiveURL);
    const BOOL ok = ReSignExtracted(oldArchiveURL, identityName, outputURL, payloadURL);
    DeleteTempFile(payloadURL);
    return ok;
}

static void Move(NSURL *source, NSURL *dest) {
    NSError *error = nil;
    [[NSFileManager defaultManager] replaceItemAtURL:dest
                                       withItemAtURL:source
                                      backupItemName:nil
                                             options:0
                                    resultingItemURL:nil
                                               error:&error];
    if (error) {
        fprintf(stderr, "While moving temp file %s over input file %s: %s",
                source.path.UTF8String, dest.path.UTF8String, error.localizedDescription.UTF8String);
    }
}

static int ResignMultiple(int argc, const char *argv[]) {
    NSInteger errorCount = 0;
    NSString *identityName = [NSString stringWithUTF8String:argv[2]];
    for (size_t i = 3; i < argc; i++) {
        NSURL *fileURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[i]]];
        NSURL *temporaryFileURL = CreateTemporaryURL([NSURL fileURLWithPath:NSTemporaryDirectory()]);
        if (!ReSign(fileURL, identityName, temporaryFileURL)) {
            errorCount += 1;
        }
        Move(temporaryFileURL, fileURL);
    }
    return errorCount == 0 ? 0 : 1;
}

static int ResignSingle(int argc, const char *argv[]) {
    NSURL *oldArchiveURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSString *identityName = [NSString stringWithUTF8String:argv[2]];
    NSURL *outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]];
    if (!ReSign(oldArchiveURL, identityName, outputURL)) {
        return 1;
    }
    return 0;
}

static void Usage(void) {
    fprintf(stderr, "Usage: resign filename.in identity filename.out\n");
    fprintf(stderr, "       resign -m identity file [file...]\n");
}

static SIGReSignMode CheckArgs(int argc, const char *argv[]) {
    if (argc < 4) {
        return SIGReSignModeError;
    }
    if (!strcmp(argv[1], "-m")) {
        return SIGReSignModeMultiple;
    }
    if (argc > 4) {
        return SIGReSignModeError;
    }
    return SIGReSignModeSingle;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        switch (CheckArgs(argc, argv)) {
            case SIGReSignModeError:
                Usage();
                return 1;
            case SIGReSignModeSingle:
                return ResignSingle(argc, argv);
            case SIGReSignModeMultiple:
                return ResignMultiple(argc, argv);
        }
    }
}
