//
//  TransferrableFile.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Foundation/Foundation.h>

@class TransferrableFile;

typedef NS_ENUM(NSInteger, TransferrableFileStatus) {
    kTransferrableFileStatusUnstarted,
    kTransferrableFileStatusStarting,
    kTransferrableFileStatusTransferring,
    kTransferrableFileStatusFinishedSuccessfully,
    kTransferrableFileStatusFinishedWithError,
    kTransferrableFileStatusCancelling,
    kTransferrableFileStatusCancelled
};

@interface TransferrableFile : NSObject

@property(atomic, assign) BOOL openWhenFinished;
@property(atomic, assign) TransferrableFileStatus status;
@property(atomic, assign) NSUInteger bytesTransferred;
@property(atomic, assign) NSInteger fileSize;  // -1 if unknown
@property(atomic, retain) TransferrableFile *successor;
@property(atomic, assign) BOOL hasPredecessor;
@property(atomic, assign) BOOL isZipOfFolder;

+ (void)lockFileName:(NSString *)name;
+ (void)unlockFileName:(NSString *)name;
+ (BOOL)fileNameIsLocked:(NSString *)name;

// These two are only needed for keyboard-interactive auth
- (NSString *)protocolName;
- (NSString *)authRequestor;

- (NSString *)displayName;
- (NSString *)shortName;
- (NSString *)subheading;
- (void)download;
- (void)upload;
- (void)stop;
- (NSString *)localPath;  // For downloads, should be nil until download is complete.
- (NSString *)error;
- (NSString *)destination;
- (NSTimeInterval)timeOfLastStatusChange;
- (BOOL)isDownloading;
- (void)didFailWithError:(NSString *)error;

#pragma mark - Utility

- (NSString *)finalDestinationForPath:(NSString *)baseName
                 destinationDirectory:(NSString *)destinationDirectory;
- (NSString *)downloadsDirectory;
- (BOOL)quarantine:(NSString *)path sourceURL:(NSURL *)sourceURL;
- (void)failedToRemoveUnquarantinedFileAt:(NSString *)path;

@end

