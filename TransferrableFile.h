//
//  TransferrableFile.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Foundation/Foundation.h>

@class TransferrableFile;

typedef enum {
    kTransferrableFileStatusUnstarted,
    kTransferrableFileStatusStarting,
    kTransferrableFileStatusTransferring,
    kTransferrableFileStatusFinishedSuccessfully,
    kTransferrableFileStatusFinishedWithError,
    kTransferrableFileStatusCancelling,
    kTransferrableFileStatusCancelled
} TransferrableFileStatus;

@interface TransferrableFile : NSObject

@property(atomic, assign) BOOL openWhenFinished;
@property(atomic, assign) TransferrableFileStatus status;
@property(atomic, assign) NSUInteger bytesTransferred;
@property(atomic, assign) int fileSize;  // -1 if unknown

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

@end

