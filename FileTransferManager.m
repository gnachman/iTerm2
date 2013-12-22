//
//  DownloadManager.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "FileTransferManager.h"
#import <Cocoa/Cocoa.h>

@interface FileTransferManager ()
@property(nonatomic, retain) NSMutableArray *files;
@end

@implementation TransferrableFile

- (id)init {
    self = [super init];
    if (self) {
        _status = kTransferrableFileStatusUnstarted;
        _fileSize = -1;
    }
    return self;
}

- (NSString *)displayName {
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

@end

@implementation FileTransferManager

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _files = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_files release];
    [super dealloc];
}

- (void)transferrableFileDidStartTransfer:(TransferrableFile *)transferrableFile {
    // TODO: Update ui
    NSLog(@"Transfer started");
}

// Number of bytes transferred has changed or total size has been discovered.
- (void)transferrableFileProgressDidChange:(TransferrableFile *)transferrableFile {
    // TODO: Update UI
    NSLog(@"Progress: %lu/%d", (unsigned long)transferrableFile.bytesTransferred, transferrableFile.fileSize);
}

// |error| is nil on success
- (void)transferrableFile:(TransferrableFile *)transferrableFile
    didFinishTransmissionWithError:(NSError *)error {
    transferrableFile.status = error ? kTransferrableFileStatusFinishedWithError : kTransferrableFileStatusFinishedSuccessfully;
    // TODO: Request user attention, update UI
    NSLog(@"Download finished. error=%@", error);
}

// Shows a modal alert with the text in |prompt| and a freeform keyboard input. Returns the
// value entered.
- (NSString *)transferrableFile:(TransferrableFile *)transferrableFile
      keyboardInteractivePrompt:(NSString *)prompt {
    NSString *text = [NSString stringWithFormat:@"%@: %@", [transferrableFile displayName], prompt];
    NSAlert *alert = [NSAlert alertWithMessageText:text
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    NSSecureTextField *input =
        [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    [alert layout];
    [[alert window] makeFirstResponder:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        [input validateEditing];
        return [input stringValue];
    } else {
        return nil;
    }
}

// Shows message, returns YES if OK, NO if Cancel
- (BOOL)transferrableFile:(TransferrableFile *)transferrableFile
           confirmMessage:(NSString *)message {
    NSString *text = [NSString stringWithFormat:@"%@: %@", [transferrableFile displayName],
                         message];
    NSAlert *alert = [NSAlert alertWithMessageText:text
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    [alert layout];
    NSInteger button = [alert runModal];
    return (button == NSAlertDefaultReturn);
}

- (void)transferrableFileDidStopTransfer:(TransferrableFile *)transferrableFile {
    NSLog(@"file transfer stopped");
}

@end
