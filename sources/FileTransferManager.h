//
//  DownloadManager.h
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import <Cocoa/Cocoa.h>
#import "TransferrableFile.h"

@class TransferrableFileMenuItemViewController;

@interface FileTransferManager : NSObject

@property(nonatomic, readonly) NSMutableArray *files;

+ (instancetype)sharedInstance;
- (void)removeItem:(TransferrableFileMenuItemViewController *)viewController;
- (void)animateImage:(NSImage *)image intoDownloadsMenuFromPoint:(NSPoint)point onScreen:(NSScreen *)screen;
- (void)openDownloadsMenu;
- (void)openUploadsMenu;

#pragma mark - Calls made by subclasses of TransferrableFile

// Connection initiation has started.
- (void)transferrableFileDidStartTransfer:(TransferrableFile *)transferrableFile;

// Stop was requested.
- (void)transferrableFileWillStop:(TransferrableFile *)transferrableFile;

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
                    title:(NSString *)title
           confirmMessage:(NSString *)message;

@end
