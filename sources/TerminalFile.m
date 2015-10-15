//
//  TerminalFile.m
//  iTerm
//
//  Created by George Nachman on 1/5/14.
//
//

#import "TerminalFile.h"
#import "FileTransferManager.h"
#import "FutureMethods.h"
#import "RegexKitLite.h"
#import <apr-1/apr_base64.h>

NSString *const kTerminalFileShouldStopNotification = @"kTerminalFileShouldStopNotification";

@interface TerminalFile ()
@property(nonatomic, retain) NSMutableString *data;
@property(nonatomic, copy) NSString *filename;  // No path, just a name.
@property(nonatomic, retain) NSString *error;
@end

@implementation TerminalFile

- (instancetype)initWithName:(NSString *)name size:(int)size {
    self = [super init];
    if (self) {
        if (!name) {
            NSSavePanel *panel = [NSSavePanel savePanel];

            if ([panel legacyRunModalForDirectory:[self downloadsDirectory] file:@"" types:nil]) {
                _localPath = [[panel legacyFilename] copy];
                _filename = [[_localPath lastPathComponent] copy];
            }
        } else {
            _filename = [[name lastPathComponent] copy];
            _localPath = [[self finalDestinationForPath:_filename
                                   destinationDirectory:[self downloadsDirectory]] copy];
        }
        self.fileSize = size;
    }
    return self;
}

- (void)dealloc {
    [_localPath release];
    [_data release];
    [_filename release];
    [_error release];
    [super dealloc];
}

#pragma mark - Overridden methods from superclass

- (NSString *)displayName {
    return self.localPath ? [self.localPath lastPathComponent] : @"Unnamed file";
}

- (NSString *)shortName {
    return self.localPath ? [self.localPath lastPathComponent] : @"Unnamed file";
}

- (NSString *)subheading {
    return self.filename ?: @"Terminal download";
}

- (void)download {
    self.status = kTransferrableFileStatusStarting;
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.localPath) {
        NSError *error;
        error = [self errorWithDescription:@"Canceled."];
        self.error = [error localizedDescription];
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:error];
    }
    self.data = [NSMutableString string];
}

- (void)upload {
    assert(false);
}

- (void)stop {
    self.status = kTransferrableFileStatusCancelling;
    [[FileTransferManager sharedInstance] transferrableFileWillStop:self];
    self.data = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kTerminalFileShouldStopNotification
                                                        object:self];
}

- (NSString *)destination  {
    return self.localPath;
}

- (BOOL)isDownloading {
    return YES;
}

#pragma mark - APIs

- (void)appendData:(NSString *)data {
    if (self.data) {
        self.status = kTransferrableFileStatusTransferring;

        // This keeps apr_base64_decode_len accurate.
        data = [data stringByReplacingOccurrencesOfRegex:@"[\r\n]" withString:@""];

        [self.data appendString:data];
        self.bytesTransferred = apr_base64_decode_len([self.data UTF8String]);
        if (self.fileSize >= 0) {
            self.bytesTransferred = MIN(self.fileSize, self.bytesTransferred);
        }
        [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
    }
}

- (void)endOfData {
    if (!self.data) {
        self.status = kTransferrableFileStatusCancelled;
        [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
        return;
    }
    const char *buffer = [self.data UTF8String];
    int destLength = apr_base64_decode_len(buffer);
    if (destLength < 1) {
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:[self errorWithDescription:@"No data received."]];
        return;
    }
    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    if (resultLength < 0) {
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:[self errorWithDescription:@"File corrupted (not valid base64)."]];
        return;
    }
    [data setLength:resultLength];
    if (![data writeToFile:self.localPath atomically:NO]) {
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:[self errorWithDescription:@"Failed to write file to disk."]];
        return;
    }

    [[FileTransferManager sharedInstance] transferrableFile:self didFinishTransmissionWithError:nil];
    return;

}

#pragma mark - Private

- (NSError *)errorWithDescription:(NSString *)description {
    return [NSError errorWithDomain:@"com.googlecode.iterm2.TerminalFile"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey:description }];
}


@end
