//
//  DownloadManager.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "FileTransferManager.h"
#import "iTermApplicationDelegate.h"
#import "TransferrableFileMenuItemViewController.h"
#import <Cocoa/Cocoa.h>

@interface FileTransferManager ()
@property(nonatomic, retain) NSMutableArray *files;
@end

@implementation FileTransferManager {
    NSMutableArray *_viewControllers;
}

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
        _viewControllers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_files release];
    [_viewControllers release];
    [super dealloc];
}

- (NSMenu *)menu {
    iTermApplicationDelegate *ad = (iTermApplicationDelegate *)[[NSApplication sharedApplication] delegate];
    return [ad downloadsMenu];
}

- (TransferrableFileMenuItemViewController *)viewControllerForTransferrableFile:(TransferrableFile *)transferrableFile {
    for (TransferrableFileMenuItemViewController *controller in _viewControllers) {
        if (controller.transferrableFile == transferrableFile) {
            return controller;
        }
    }
    return nil;
}

- (NSMenuItem *)menuItemForTransferrableFile:(TransferrableFile *)transferrableFile {
    NSMenuItem *item = [[NSMenuItem alloc] init];
    TransferrableFileMenuItemViewController *controller =
        [[[TransferrableFileMenuItemViewController alloc] initWithTransferrableFile:transferrableFile] autorelease];
    [_viewControllers addObject:controller];
    item.view = [controller view];
    [item setEnabled:YES];
    [item setTarget:controller];
    [item setAction:@selector(itemSelected:)];
    
    NSMenu *submenu = [[[NSMenu alloc] init] autorelease];
    NSMenuItem *subItem = [[[NSMenuItem alloc] initWithTitle:@"Stop"
                                                      action:@selector(stop:)
                                               keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.stopSubItem = subItem;
    
    subItem = [[[NSMenuItem alloc] initWithTitle:@"Show in Finder"
                                          action:@selector(showInFinder:)
                                   keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.showInFinderSubItem = subItem;

    subItem = [[[NSMenuItem alloc] initWithTitle:@"Remove from List"
                                          action:@selector(removeFromList:)
                                   keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.removeFromListSubItem = subItem;

    subItem = [[[NSMenuItem alloc] initWithTitle:@"Open"
                                          action:@selector(open:)
                                   keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.openSubItem = subItem;

    item.submenu = submenu;
    
    [controller update];
    return item;
}

- (void)transferrableFileDidStartTransfer:(TransferrableFile *)transferrableFile {
    NSLog(@"Transfer started");
    [[self menu] addItem:[self menuItemForTransferrableFile:transferrableFile]];
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

// Number of bytes transferred has changed or total size has been discovered.
- (void)transferrableFileProgressDidChange:(TransferrableFile *)transferrableFile {
    NSLog(@"Progress: %lu/%d", (unsigned long)transferrableFile.bytesTransferred, transferrableFile.fileSize);
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

// |error| is nil on success
- (void)transferrableFile:(TransferrableFile *)transferrableFile
    didFinishTransmissionWithError:(NSError *)error {
    transferrableFile.status = error ? kTransferrableFileStatusFinishedWithError : kTransferrableFileStatusFinishedSuccessfully;
    NSLog(@"Download finished. error=%@", error);

    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

- (void)transferrableFileWillStop:(TransferrableFile *)transferrableFile {
    NSLog(@"file transfer stop requested");
    transferrableFile.status = kTransferrableFileStatusCancelling;
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

- (void)transferrableFileDidStopTransfer:(TransferrableFile *)transferrableFile {
    NSLog(@"file transfer stopped");
    transferrableFile.status = kTransferrableFileStatusCancelled;
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
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

- (void)removeItem:(TransferrableFileMenuItemViewController *)viewController {
    NSMenuItem *item = [viewController.view enclosingMenuItem];
    [[item menu] removeItem:item];
    [_viewControllers removeObject:viewController];
}

@end
