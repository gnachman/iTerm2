//
//  TransferrableFile.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

typedef void (^TransferrableFileCompletionBlock)(BOOL success, NSString * _Nullable error);

@interface TransferrableFile : NSObject

@property(atomic, assign) BOOL openWhenFinished;
@property(atomic, assign) TransferrableFileStatus status;
@property(atomic, assign) NSUInteger bytesTransferred;
@property(atomic, assign) NSInteger fileSize;  // -1 if unknown
@property(atomic, retain, nullable) TransferrableFile *successor;
@property(atomic, assign) BOOL hasPredecessor;
@property(atomic, assign) BOOL isZipOfFolder;
@property(atomic, copy, nullable) TransferrableFileCompletionBlock completionBlock;

+ (void)lockFileName:(NSString *)name;
+ (void)unlockFileName:(NSString *)name;
+ (BOOL)fileNameIsLocked:(NSString *)name;

// These two are only needed for keyboard-interactive auth
- (nullable NSString *)protocolName;
- (nullable NSString *)authRequestor;

- (nullable NSString *)displayName;
- (nullable NSString *)shortName;
- (nullable NSString *)subheading;
- (void)download;
- (void)upload;
- (void)stop;
- (nullable NSString *)localPath;  // For downloads, should be nil until download is complete.
- (nullable NSString *)error;
- (nullable NSString *)destination;
- (NSTimeInterval)timeOfLastStatusChange;
- (BOOL)isDownloading;
- (void)didFailWithError:(NSString *)error;

#pragma mark - Utility

- (nullable NSString *)finalDestinationForPath:(NSString *)baseName
                          destinationDirectory:(NSString *)destinationDirectory
                                        prompt:(BOOL)prompt;
- (NSString *)downloadsDirectory;
- (BOOL)quarantine:(nullable NSString *)path sourceURL:(nullable NSURL *)sourceURL;
- (void)failedToRemoveUnquarantinedFileAt:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

