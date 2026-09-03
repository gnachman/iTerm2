//
//  TransferrableFile.m
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import "TransferrableFile.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"
#import "iTermNotificationController.h"
#import "iTermWarning.h"

@implementation TransferrableFile {
    NSTimeInterval _timeOfLastStatusChange;
    TransferrableFileStatus _status;
    TransferrableFile *_successor;
}

static NSMutableSet<NSString *> *iTermTransferrableFileLockedFileNames(void) {
    static NSMutableSet<NSString *> *locks;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locks = [[NSMutableSet alloc] init];
    });
    return locks;
}

+ (void)lockFileName:(NSString *)name {
    if (name) {
        [iTermTransferrableFileLockedFileNames() addObject:name];
    }
}

+ (void)unlockFileName:(NSString *)name {
    if (name) {
        [iTermTransferrableFileLockedFileNames() removeObject:name];
    }
}

+ (BOOL)fileNameIsLocked:(NSString *)name {
    if (!name) {
        return NO;
    }
    return [iTermTransferrableFileLockedFileNames() containsObject:name];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = kTransferrableFileStatusUnstarted;
        _fileSize = -1;
    }
    return self;
}

- (NSString *)protocolName {
    assert(false);
}

- (NSString *)authRequestor {
    assert(false);
}

- (NSString *)displayName {
    assert(false);
}

- (NSString *)shortName {
    assert(false);
}

- (NSString *)subheading {
    assert(false);
}

- (void)download {
    assert(false);
}

- (void)upload {
    assert(false);
}

- (void)stop {
    assert(false);
}

- (NSString *)localPath {
    assert(false);
}

- (NSString *)error {
    assert(false);
}

- (NSString *)destination  {
    assert(false);
}

- (BOOL)isDownloading {
    assert(false);
}

- (NSString *)finalDestinationForPath:(NSString *)originalBaseName
                 destinationDirectory:(NSString *)destinationDirectory
                               prompt:(BOOL)prompt {
    NSString *baseName = originalBaseName;
    if (self.isZipOfFolder) {
        baseName = [baseName stringByAppendingString:@".zip"];
    }
    NSString *name = baseName;
    NSString *finalDestination = nil;
    int retries = 0;
    do {
        finalDestination = [destinationDirectory stringByAppendingPathComponent:name];
        ++retries;
        NSRange rangeOfDot = [baseName rangeOfString:@"."];
        NSString *prefix = baseName;
        NSString *suffix = @"";
        if (rangeOfDot.length > 0) {
            prefix = [baseName substringToIndex:rangeOfDot.location];
            suffix = [baseName substringFromIndex:rangeOfDot.location];
        }
        name = [NSString stringWithFormat:@"%@ (%d)%@", prefix, retries, suffix];
    } while ([[NSFileManager defaultManager] fileExistsAtPath:finalDestination] ||
             [TransferrableFile fileNameIsLocked:finalDestination]);
    if (retries == 1 || !prompt) {
        return finalDestination;
    }
    NSString *message = [NSString stringWithFormat:ITLocalize(@"TransferrableFile_FormattedFacing_AFileNamedAlreadyExistsKeepBoth_FORMAT", @"A file named %1$@ already exists. Keep both files or replace the existing file?",@"Formatted user-facing text in finalDestinationForPath:(NSString *)originalBaseName"), baseName];
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:message
                                                                       actions:@[ ITLocalize(@"TransferrableFile_Action_KeepBoth", @"Keep Both", @"Action title in finalDestinationForPath:"), ITLocalize(@"TransferrableFile_Action_Replace", @"Replace", @"Title in finalDestinationForPath:") ]
                                                                     accessory:nil
                                                                    identifier:@"NoSyncOverwriteOrReplaceFile"
                                                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                                                       heading:ITLocalize(@"TransferrableFile_AlertHeading_OverwriteExistingFile", @"Overwrite existing file?",@"Alert heading in finalDestinationForPath:(NSString *)originalBaseName")
                                                                        window:nil];
    if (selection == kiTermWarningSelection1) {
        return [destinationDirectory stringByAppendingPathComponent:baseName];
    }
    return finalDestination;
}

- (NSString *)downloadsDirectory {
    return [[NSFileManager defaultManager] downloadsDirectory] ?: NSHomeDirectory();
}

- (void)setSuccessor:(TransferrableFile *)successor {
    @synchronized(self) {
        [_successor autorelease];
        _successor = [successor retain];
        successor.hasPredecessor = YES;
    }
}

- (TransferrableFile *)successor {
    @synchronized(self) {
        return _successor;
    }
}

- (void)didFailWithError:(NSString *)error {
    RLog(@"didFailWithError:%@", error);
    @synchronized(self) {
        if (_status != kTransferrableFileStatusFinishedWithError) {
            _status = kTransferrableFileStatusFinishedWithError;
            _timeOfLastStatusChange = [NSDate timeIntervalSinceReferenceDate];
            [[iTermNotificationController sharedInstance] notify:error];
        }
    }
}

- (void)setStatus:(TransferrableFileStatus)status {
    DLog(@"setStatus:%@\n%@", @(status), [NSThread callStackSymbols]);
    @synchronized(self) {
        if (status != _status) {
            _status = status;
            _timeOfLastStatusChange = [NSDate timeIntervalSinceReferenceDate];
            switch (status) {
                case kTransferrableFileStatusUnstarted:
                case kTransferrableFileStatusStarting:
                case kTransferrableFileStatusTransferring:
                case kTransferrableFileStatusCancelling:
                case kTransferrableFileStatusCancelled:
                    break;

                case kTransferrableFileStatusFinishedSuccessfully:
                    [[iTermNotificationController sharedInstance] notify:
                        [NSString stringWithFormat:ITLocalize(@"TransferrableFile_FormattedFacing_FinishedFor_FORMAT", @"%1$@ finished for “%2$@”.",@"Formatted user-facing text in setStatus:(TransferrableFileStatus)status"),
                            self.isDownloading ? ITLocalize(@"TransferrableFile_Facing_Download", @"Download", @"Text shown in setStatus:: Download") : ITLocalize(@"COMMON_UPLOAD", @"Upload", @"Text shown in setStatus:: Upload"), [self shortName]]];
                    break;

                case kTransferrableFileStatusFinishedWithError:
                    [[iTermNotificationController sharedInstance] notify:
                     [NSString stringWithFormat:ITLocalize(@"TransferrableFile_FormattedFacing_FailedFor_FORMAT", @"%1$@ failed for “%2$@”.",@"Formatted user-facing text in setStatus:(TransferrableFileStatus)status"),
                      self.isDownloading ? ITLocalize(@"TransferrableFile_Facing_Download", @"Download", @"Text shown in setStatus:: Download") : ITLocalize(@"COMMON_UPLOAD", @"Upload", @"Text shown in setStatus:: Upload"), [self shortName]]];
            }
        }
    }
}

- (TransferrableFileStatus)status {
    @synchronized(self) {
        return _status;
    }
}

- (NSTimeInterval)timeOfLastStatusChange {
    return _timeOfLastStatusChange;
}

- (void)failedToRemoveUnquarantinedFileAt:(NSString *)path {
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:ITLocalize(@"TransferrableFile_Alert_TheFileAtCouldNotBeQuarantined_FORMAT", @"The file at “%1$@” could not be quarantined or deleted! It is dangerous and should be removed.", @"Alert title in failedToRemoveUnquarantinedFileAt:"), path]
                               actions:@[ ITLocalize(@"COMMON_OK", @"OK", @"Action title in failedToRemoveUnquarantinedFileAt:") ]
                             accessory:nil
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                               heading:ITLocalize(@"TransferrableFile_AlertHeading_Danger", @"Danger!",@"Alert heading in failedToRemoveUnquarantinedFileAt:(NSString *)path")
                                window:nil];
}

- (BOOL)quarantine:(NSString *)path sourceURL:(NSURL *)sourceURL {
    if (!path) {
        XLog(@"Nil path to quarantine");
        return NO;
    }
    NSURL *url = [NSURL fileURLWithPath:path];

    NSMutableDictionary *properties = nil;
    {
        NSError *error = nil;
        NSDictionary *temp;
        const BOOL ok = [url getResourceValue:&temp
                                       forKey:NSURLQuarantinePropertiesKey
                                        error:&error];
        if (!ok) {
            XLog(@"Get quarantine of %@ failed: %@", path, error);
            return NO;
        }
        if (temp && ![temp isKindOfClass:[NSDictionary class]]) {
            XLog(@"Quarantine of wrong class: %@", NSStringFromClass([temp class]));
            return NO;
        }
        properties = [[temp ?: @{} mutableCopy] autorelease];
    }

    NSBundle *bundle = [NSBundle mainBundle];
    NSDictionary *info = bundle.infoDictionary;
    properties[(__bridge NSString *)kLSQuarantineAgentNameKey] = info[(__bridge NSString *)kCFBundleNameKey] ?: @"iTerm2";
    properties[(__bridge NSString *)kLSQuarantineAgentBundleIdentifierKey] = info[(__bridge NSString *)kCFBundleIdentifierKey] ?: @"com.googlecode.iterm2";
    if (sourceURL.absoluteString) {
        properties[(__bridge NSString *)kLSQuarantineDataURLKey] = sourceURL.absoluteString;
    }
    properties[(__bridge NSString *)kLSQuarantineTimeStampKey] = [NSDate date];
    properties[(__bridge NSString *)kLSQuarantineTypeKey] = (__bridge NSString *)kLSQuarantineTypeOtherDownload;

    {
        NSError *error = nil;
        const BOOL ok = [url setResourceValue:properties
                                       forKey:NSURLQuarantinePropertiesKey
                                        error:&error];
        if (!ok) {
            XLog(@"Set quarantine of %@ failed: %@", path, error);
            return NO;
        }
    }
    return YES;
}

@end

