//
//  TransferrableFile.m
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import "TransferrableFile.h"

#import "NSFileManager+iTerm.h"
#import "iTermNotificationController.h"

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
    [iTermTransferrableFileLockedFileNames() addObject:name];
}

+ (void)unlockFileName:(NSString *)name {
    [iTermTransferrableFileLockedFileNames() removeObject:name];
}

+ (BOOL)fileNameIsLocked:(NSString *)name {
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

- (NSString *)finalDestinationForPath:(NSString *)baseName
                 destinationDirectory:(NSString *)destinationDirectory {
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

- (void)setStatus:(TransferrableFileStatus)status {
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
                        [NSString stringWithFormat:@"%@ of “%@” finished!",
                            self.isDownloading ? @"Download" : @"Upload", [self shortName]]];
                    break;

                case kTransferrableFileStatusFinishedWithError:
                    [[iTermNotificationController sharedInstance] notify:
                     [NSString stringWithFormat:@"%@ of “%@” failed.",
                      self.isDownloading ? @"Download" : @"Upload", [self shortName]]];
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

@end

