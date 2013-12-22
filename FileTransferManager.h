//
//  DownloadManager.h
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import <Foundation/Foundation.h>

@class TransferrableFile;

typedef enum {
    kTransferrableFileStatusUnstarted,
    kTransferrableFileStatusStarting,
    kTransferrableFileStatusTransferring,
    kTransferrableFileStatusFinishedSuccessfully,
    kTransferrableFileStatusFinishedWithError
} TransferrableFileStatus;

@interface TransferrableFile : NSObject

@property(atomic, assign) BOOL openWhenFinished;
@property(atomic, assign) TransferrableFileStatus status;
@property(atomic, assign) NSUInteger bytesTransferred;
@property(atomic, assign) int fileSize;  // -1 if unknown

- (NSString *)displayName;
- (void)download;
- (void)upload;
- (void)stop;
- (NSString *)localPath;  // For downloads, should be nil until download is complete.

@end

@interface FileTransferManager : NSObject

@property(nonatomic, readonly) NSMutableArray *files;

+ (instancetype)sharedInstance;

#pragma mark - Calls made by subclasses of TransferrableFile

// Connection initiation has started.
- (void)transferrableFileDidStartTransfer:(TransferrableFile *)transferrableFile;

// A transfer stopped with -stop has finally stopped.
- (void)transferrableFileDidStopTransfer:(TransferrableFile *)transferrableFile;

// Number of bytes transferred has changed or total size has been discovered.
- (void)transferrableFileProgressDidChange:(TransferrableFile *)transferrableFile;

// |error| is nil on success
- (void)transferrableFile:(TransferrableFile *)transferrableFile
    didFinishTransmissionWithError:(NSError *)error;

// Shows a modal alert with the text in |prompt| and a freeform keyboard input. Returns the
// value entered.
- (NSString *)transferrableFile:(TransferrableFile *)transferrableFile
      keyboardInteractivePrompt:(NSString *)prompt;

// Shows message, returns YES if OK, NO if Cancel
- (BOOL)transferrableFile:(TransferrableFile *)transferrableFile
           confirmMessage:(NSString *)message;

@end
