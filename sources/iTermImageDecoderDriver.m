//
//  iTermImageDecoderDriver.m
//  iTerm2
//
//  Created by George Nachman on 8/30/16.
//
//
#import "iTermImageDecoderDriver.h"

#import "DebugLogging.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#include <syslog.h>

#include <errno.h>
#include <libgen.h>
#include <string.h>

@interface NSString(Sandbox)
- (NSString *)stringByEscapingForSandboxLiteral;
@end

@implementation NSString(Sandbox)

// Adapted from Chromium's Sandbox::QuotePlainString
- (NSString *)stringByEscapingForSandboxLiteral {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        if (c < 128) {
            switch (c) {
                case '\b':
                    [result appendString:@"\\b"];
                    break;
                case '\f':
                    [result appendString:@"\\f"];
                    break;
                case '\n':
                    [result appendString:@"\\n"];
                    break;
                case '\r':
                    [result appendString:@"\\r"];
                    break;
                case '\t':
                    [result appendString:@"\\t"];
                    break;
                case '\\':
                    [result appendString:@"\\\\"];
                    break;
                case '"':
                    [result appendString:@"\\\""];
                    break;
                default:
                    [result appendCharacter:c];
                    break;
            }
        } else {
            [result appendFormat:@"\\u%04X", (unsigned int)c];
        }
    }
    return result;
}

@end

static void Dup2OrDie(int source, int dest) {
    int rc;
    do {
        rc = dup2(source, dest);
    } while (rc == -1 && errno == EINTR);
    if (rc == -1) {
        exit(1);
    }
}

static void ExecImageDecoder(char *executable, char *sandbox, int jsonFD, int compressedDataFD, int dtablesize) {
    int numFileDescriptorsToPreserve = 0;

    Dup2OrDie(compressedDataFD, numFileDescriptorsToPreserve++);
    Dup2OrDie(jsonFD, numFileDescriptorsToPreserve++);

    // Do not start the new process with a signal handler.
    signal(SIGCHLD, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGPIPE);
    sigprocmask(SIG_UNBLOCK, &signals, NULL);

    // Make sure all other file descriptors are closed.
    for (int j = numFileDescriptorsToPreserve; j < dtablesize; j++) {
        close(j);
    }

    char *args[] = {
        "sandbox-exec",
        "-p",
        sandbox,
        executable,
        NULL
    };

    execvp("/usr/bin/sandbox-exec", args);
}

@implementation iTermImageDecoderDriver

- (NSString *)executable {
    return [[NSBundle bundleForClass:self.class] pathForResource:@"image_decoder" ofType:nil];
}

- (NSString *)sandbox {
    NSString *sandboxFileName = [[NSBundle bundleForClass:self.class] pathForResource:@"image_decoder" ofType:@"sb"];
    NSString *sandboxContents = [NSString stringWithContentsOfFile:sandboxFileName encoding:NSUTF8StringEncoding error:nil];
    NSString *executable = [self executable];
    if (!sandboxFileName || !sandboxContents || !executable) {
        return nil;
    }
    NSDictionary *subs = @{ @"@PATH_TO_EXECUTABLE@": [[executable stringByDeletingLastPathComponent] stringByEscapingForSandboxLiteral],
                            @"@EXECUTABLE@": [[executable lastPathComponent] stringByEscapingForSandboxLiteral],
                            @"@HOME_DIRECTORY@": NSHomeDirectory() ?: @"//bogus//" };
    for (NSString *key in subs) {
        sandboxContents = [sandboxContents stringByReplacingOccurrencesOfString:key withString:subs[key]];
    }
    NSArray *lines = [sandboxContents componentsSeparatedByString:@"\n"];
    return [lines componentsJoinedByString:@" "];
}

- (NSData *)decompressImageData:(NSData *)compressedData
         fromChildWithProcessID:(pid_t)pid
                        writeFD:(int)writeFD
                         readFD:(int)readFD {
    DLog(@"Write compressed data to sandbox");
    BOOL ok = [self writeCompressedImage:compressedData toFileDescriptor:writeFD];
    if (ok) {
        // Close the write file descriptor so image_decoder knows to stop reading.
        close(writeFD);
        writeFD = -1;
    }

    NSData *data = nil;
    if (ok) {
        DLog(@"Read decompressed data from sandbox");
        data = [self readDecompressedImageFromFileDescriptor:readFD];
        ok = data != nil;
    }

    if (writeFD != -1) {
        close(writeFD);
    }
    close(readFD);
    if (!ok) {
        kill(pid, SIGKILL);
    }
    [self reapProcessID:pid];

    DLog(@"Decompression ok=%@", @(ok));
    return data;
}

- (BOOL)writeCompressedImage:(NSData *)compressedData toFileDescriptor:(int)fd {
    NSFileHandle *fileHandle = [[[NSFileHandle alloc] initWithFileDescriptor:fd] autorelease];
    @try {
        [fileHandle writeData:compressedData];
    } @catch (NSException *exception) {
        XLog(@"Couldn't write: %@", exception);
        return NO;
    }
    return YES;
}

- (NSData *)readDecompressedImageFromFileDescriptor:(int)fd {
    NSFileHandle *fileHandle = [[[NSFileHandle alloc] initWithFileDescriptor:fd] autorelease];
    @try {
        return [fileHandle readDataToEndOfFile];
    } @catch (NSException *exception) {
        XLog(@"Couldn't read: %@", exception);
        return nil;
    }
}

// Returns YES if the process exited normally.
- (BOOL)reapProcessID:(pid_t)pid {
    pid_t rc;
    int stat_loc;
    do {
        rc = waitpid(pid, &stat_loc, 0);
    } while (rc == -1 && errno == EINTR);
    return rc == pid && WIFEXITED(stat_loc) && WEXITSTATUS(stat_loc) == 0;
}

- (NSData *)jsonForCompressedImageData:(NSData *)compressedData {
    NSString *sandboxString = [self sandbox];
    if (!sandboxString) {
        return nil;
    }
    int jsonFDs[2] = { 0, 0 };
    if (pipe(jsonFDs)) {
        XLog(@"Failed to create a pipe: %s", strerror(errno));
        return nil;
    }

    int compressedImageFDs[2] = { 0, 0 };
    if (pipe(compressedImageFDs)) {
        XLog(@"Failed to create a pipe: %s", strerror(errno));
        close(jsonFDs[0]);
        close(jsonFDs[1]);
        return nil;
    }

    NSString *executable = [self executable];
    char *utf8Executable = strdup([executable UTF8String]);
    char *sandbox = strdup([sandboxString UTF8String]);
    int dtablesize = getdtablesize();

    DLog(@"sandbox-exec -p '%@' '%@'", sandboxString, executable);
    pid_t pid = fork();
    switch (pid) {
        case -1:
            // error
            NSLog(@"Fork failed: %s", strerror(errno));
            free(sandbox);
            free(utf8Executable);
            return nil;

        case 0:
            // child
            close(jsonFDs[0]);
            close(compressedImageFDs[1]);
            ExecImageDecoder(utf8Executable, sandbox, jsonFDs[1], compressedImageFDs[0], dtablesize);
            exit(1);
            return nil;

        default: {
            // parent

            // Get rid of resources only needed by the child.
            free(utf8Executable);
            free(sandbox);
            close(jsonFDs[1]);
            close(compressedImageFDs[0]);

            // Write a compressed image and read back a blob of JSON.
            return [self decompressImageData:compressedData
                      fromChildWithProcessID:pid
                                     writeFD:compressedImageFDs[1]
                                      readFD:jsonFDs[0]];
        }
    }
}

@end
