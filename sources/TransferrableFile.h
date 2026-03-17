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

+ (void)lockFileName:(NSString * _Nonnull)name;
+ (void)unlockFileName:(NSString * _Nonnull)name;
+ (BOOL)fileNameIsLocked:(NSString * _Nonnull)name;

// These two are only needed for keyboard-interactive auth
- (NSString * _Nullable)protocolName;
- (NSString * _Nullable)authRequestor;

- (NSString * _Nullable)displayName;
- (NSString * _Nullable)shortName;
- (NSString * _Nullable)subheading;
- (void)download;
- (void)upload;
- (void)stop;
- (NSString * _Nullable)localPath;  // For downloads, should be nil until download is complete.
- (NSString * _Nullable)error;
- (NSString * _Nullable)destination;
- (NSTimeInterval)timeOfLastStatusChange;
- (BOOL)isDownloading;
- (void)didFailWithError:(NSString * _Nullable)error;

#pragma mark - Utility

- (NSString * _Nullable)finalDestinationForPath:(NSString * _Nonnull)baseName
                 destinationDirectory:(NSString * _Nonnull)destinationDirectory
                               prompt:(BOOL)prompt;
- (NSString * _Nullable)downloadsDirectory;
- (BOOL)quarantine:(NSString * _Nullable)path sourceURL:(NSURL * _Nullable)sourceURL;
- (void)failedToRemoveUnquarantinedFileAt:(NSString * _Nullable)path;

@end

