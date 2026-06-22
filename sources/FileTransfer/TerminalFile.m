//
//  TerminalFile.m
//  iTerm
//
//  Created by George Nachman on 1/5/14.
//
//

#import "TerminalFile.h"

#import "DebugLogging.h"
#import "FileTransferManager.h"
#import "FutureMethods.h"
#import "NSSavePanel+iTerm.h"
#import "RegexKitLite.h"
#import "iTermWarning.h"

#import <apr-1/apr_base64.h>

NSString *const kTerminalFileShouldStopNotification = @"kTerminalFileShouldStopNotification";

@interface TerminalFile ()
@property(nonatomic, strong) NSMutableString *data;
@property(nonatomic, copy) NSString *filename;  // No path, just a name.
@property(nonatomic, strong) NSString *error;
@end

@implementation TerminalFileDownload

- (instancetype)initWithName:(NSString *)name size:(NSInteger)size window:(NSWindow *)window {
    self = [super initWithName:name size:size window:window];
    if (self) {
        if (self.localPath) {
            [TransferrableFile lockFileName:self.localPath];
        }
    }
    return self;
}

// Only real downloads (not uploads, which share TerminalFile’s initializer) ask where to save.
- (BOOL)offersDownloadLocationPrompt {
    return YES;
}

@end

@implementation TerminalFile

- (instancetype)initWithName:(NSString *)name size:(NSInteger)size {
    return [self initWithName:name size:size window:nil];
}

- (instancetype)initWithName:(NSString *)name size:(NSInteger)size window:(NSWindow *)window {
    self = [super init];
    if (self) {
        if (!name) {
            // The sender didn’t provide a name, so we have no choice but to ask where to save.
            [self promptForLocalPathWithSuggestedName:nil];
        } else {
            _filename = [[name lastPathComponent] copy];
            if ([self offersDownloadLocationPrompt] && [self shouldPromptForDownloadLocationInWindow:window]) {
                [self promptForLocalPathWithSuggestedName:_filename];
            } else {
                _localPath = [[self finalDestinationForPath:_filename
                                       destinationDirectory:[self downloadsDirectory]
                                                     prompt:YES] copy];
            }
        }
        self.fileSize = size;
    }
    return self;
}

// Subclasses that represent actual downloads return YES to be offered a save-location choice.
- (BOOL)offersDownloadLocationPrompt {
    return NO;
}

// Asks the user whether to save downloads to the Downloads folder or to choose a destination.
// The choice is silenceable, so a user can make it permanent in either direction. The question is
// attached to `window` so it matches the terminal-initiated download confirmation.
- (BOOL)shouldPromptForDownloadLocationInWindow:(NSWindow *)window {
    const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"Where would you like to save this download?"
                                   actions:@[ @"Save to Downloads", @"Choose…" ]
                                 accessory:nil
                                identifier:@"NoSyncPromptForDownloadLocation"
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:@"Save Terminal-Initiated Download"
                                    window:window];
    return selection == kiTermWarningSelection1;
}

// Runs a save panel anchored at the downloads directory and records the chosen path. Leaves
// _localPath nil if the user cancels, which -download treats as a canceled transfer.
//
// Unlike the "Save to Downloads" branch, the chosen path is used verbatim: we intentionally trust
// the user's explicit selection rather than running it through finalDestinationForPath:, which would
// rename it to "foo (1)" on collision. NSSavePanel already handles the replace-existing-file prompt
// for on-disk collisions. The one uncovered case, two concurrent terminal downloads the user points
// at the identical path, is rare enough to accept over surprising the user with a renamed file.
- (void)promptForLocalPathWithSuggestedName:(NSString *)suggestedName {
    NSSavePanel *panel = [NSSavePanel savePanel];

    NSString *path = [self downloadsDirectory];
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [NSSavePanel setDirectoryURL:url onceForID:@"TerminalFile" savePanel:panel];
    }
    panel.nameFieldStringValue = suggestedName ?: @"";

    if ([panel runModal] == NSModalResponseOK) {
        _localPath = [panel.URL.path copy];
        _filename = [[_localPath lastPathComponent] copy];
    }
}

- (void)dealloc {
    [TransferrableFile unlockFileName:_localPath];
}

#pragma mark - Overridden methods from superclass

- (void)didFailWithError:(NSString *)error {
    @synchronized (self) {
        [super didFailWithError:error];
        self.error = error;
    }
}

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
        // The user canceled the save panel (or no destination could be chosen). Report the
        // cancellation and leave self.data nil so appendData: no-ops on any further chunks and
        // handleEndOfData treats the transfer as canceled instead of trying to write to nil.
        NSError *error;
        error = [self errorWithDescription:@"Canceled."];
        self.error = [error localizedDescription];
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:error];
        return;
    }
    self.data = [NSMutableString string];
}

- (void)upload {
    assert(false);
}

- (void)stop {
    DLog(@"Stop file download.\n%@", [NSThread callStackSymbols]);
    self.status = kTransferrableFileStatusCancelling;
    [[FileTransferManager sharedInstance] transferrableFileWillStop:self];
    self.data = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kTerminalFileShouldStopNotification
                                                        object:self];
    [TransferrableFile unlockFileName:_localPath];
}

- (NSString *)destination  {
    return self.localPath;
}

- (BOOL)isDownloading {
    return YES;
}

#pragma mark - APIs

- (BOOL)appendData:(NSString *)data {
    if (!self.data) {
        return YES;
    }
    self.status = kTransferrableFileStatusTransferring;

    // This keeps apr_base64_decode_len accurate.
    data = [data stringByReplacingOccurrencesOfRegex:@"[\r\n]" withString:@""];

    [self.data appendString:data];
    double approximateSize = self.data.length;
    approximateSize *= 3.0 / 4.0;
    self.bytesTransferred = ceil(approximateSize);
    if (self.fileSize >= 0) {
        self.bytesTransferred = MIN(self.fileSize, self.bytesTransferred);
    }
    [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
    if (approximateSize > self.fileSize + 5) {
        DLog(@"Have %@ bytes of base64 which encodes as much as %@ but the file's declared size is %@",
             @(self.data.length), @(approximateSize + 4), @(self.fileSize));
        return NO;
    }
    return YES;
}

- (NSInteger)length {
    return self.data.length;
}

- (void)endOfData {
    [self handleEndOfData];
    [TransferrableFile unlockFileName:_localPath];
}

- (void)handleEndOfData {
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
    NSError *error = nil;
    if (![data writeToFile:self.localPath options:NSDataWritingAtomic error:&error]) {
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:[self errorWithDescription:error.localizedDescription]];
        return;
    }
    if (![self quarantine:self.localPath sourceURL:nil]) {
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:[self errorWithDescription:@"Failed to set quarantine."]];
        NSError *error = nil;
        const BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:self.localPath error:&error];
        if (!ok || error) {
            // Avoid runloop in side-effect.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self failedToRemoveUnquarantinedFileAt:self.localPath];
            });
        }
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

@implementation TerminalFileUpload

- (BOOL)isDownloading {
    return NO;
}

- (void)upload {
    self.status = kTransferrableFileStatusTransferring;
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];
}

- (void)endOfData {
    self.status = kTransferrableFileStatusCancelled;
    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
}

- (void)didUploadBytes:(NSInteger)count {
    self.bytesTransferred = count;
    if (count == self.fileSize) {
        [[FileTransferManager sharedInstance] transferrableFile:self didFinishTransmissionWithError:nil];
    } else {
        [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
    }
}

- (NSString *)finalDestinationForPath:(NSString *)originalBaseName
                 destinationDirectory:(NSString *)destinationDirectory
                               prompt:(BOOL)prompt {
    return originalBaseName;
}

@end
