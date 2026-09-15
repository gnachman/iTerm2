//
//  DownloadManager.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "FileTransferManager.h"
#import "iTermApplicationDelegate.h"
#import "iTermPasswordManagerWindowController.h"
#import "NSArray+iTerm.h"
#import "TransferrableFileMenuItemViewController.h"

// Finished downloads will be automatically removed from the downloads menu after this number of
// seconds.
static const NSTimeInterval kMaximumTimeToKeepFinishedDownload = 24 * 60 * 60;

@interface FileTransferManager ()<iTermPasswordManagerDelegate>
@property(nonatomic, retain) NSMutableArray *files;
@end

@implementation FileTransferManager {
    NSMutableArray *_viewControllers;
    NSTimer *_timer;  // cleanUpMenus timer. weak reference.
    iTermPasswordManagerWindowController *_passwordManagerWindowController;
    void (^_passwordCompletion)(NSString *password);
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _files = [[NSMutableArray alloc] init];
        _viewControllers = [[NSMutableArray alloc] init];
        _timer = [NSTimer scheduledTimerWithTimeInterval:60 * 10
                                                  target:self
                                                selector:@selector(cleanUpMenus)
                                                userInfo:nil
                                                 repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_files release];
    [_viewControllers release];
    [super dealloc];
}

- (void)cleanUpMenus {
    NSMutableArray *controllersToRemove = [NSMutableArray array];
    for (TransferrableFileMenuItemViewController *controller in _viewControllers) {
        if ([controller timeSinceLastStatusChange] > kMaximumTimeToKeepFinishedDownload &&
            controller.transferrableFile.status != kTransferrableFileStatusStarting &&
            controller.transferrableFile.status != kTransferrableFileStatusTransferring &&
            controller.transferrableFile.status != kTransferrableFileStatusCancelling) {
            [controller.view.enclosingMenuItem.menu removeItem:controller.view.enclosingMenuItem];
            [controllersToRemove addObject:controller];
        }
    }

    for (TransferrableFileMenuItemViewController *controller in controllersToRemove) {
        [_viewControllers removeObject:controller];
    }
}

- (NSMenu *)downloadsMenu {
    iTermApplicationDelegate *ad = [iTermApplication.sharedApplication delegate];
    return [ad downloadsMenu];
}

- (NSMenu *)uploadsMenu {
    iTermApplicationDelegate *ad = [iTermApplication.sharedApplication delegate];
    return [ad uploadsMenu];
}

- (void)animateImage:(NSImage *)image
            intoMenu:(AXUIElementRef)menuElement
           fromPoint:(NSPoint)point
            onScreen:(NSScreen *)screen {
    if (!menuElement) {
        return;
    }
    CFTypeRef temp = NULL;
    AXUIElementCopyAttributeValue(menuElement, kAXPositionAttribute, (CFTypeRef *)&temp);
    if (!temp) {
        return;
    }

    CGPoint position;
    AXValueGetValue(temp, kAXValueCGPointType, &position);
    CFRelease(temp);
    CFRelease(menuElement);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(point.x,
                                                                        point.y,
                                                                        image.size.width,
                                                                        image.size.height)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    NSImageView  *imageView =
        [[[NSImageView alloc] initWithFrame:NSMakeRect(0,
                                                       0,
                                                       image.size.width,
                                                       image.size.height)] autorelease];
    imageView.image = image;
    window.contentView = imageView;
    [window makeKeyAndOrderFront:nil];
    [window setLevel:NSMainMenuWindowLevel];

    // Todo: deal with multiple screens, mavericks
    const CGFloat menuBarHeight =
        [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    position.y = screen.frame.size.height - position.y - menuBarHeight;

    [window.animator setFrame:NSMakeRect(position.x,
                                         position.y,
                                         window.frame.size.width,
                                         window.frame.size.height)
                      display:YES];
    [self performSelector:@selector(fadeWindowOut:)
               withObject:window
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)animateImage:(NSImage *)image intoDownloadsMenuFromPoint:(NSPoint)point onScreen:(NSScreen *)screen {
    AXUIElementRef menuElement = [self downloadsMenuElement];
    [self animateImage:image intoMenu:menuElement fromPoint:point onScreen:screen];
}

- (void)fadeWindowOut:(NSWindow *)window {
    // Fade the animation window out, then take it off screen and release it. Simply releasing the
    // window is not enough: an on-screen NSWindow is retained by AppKit's window list, so -release
    // only balances the +1 from -alloc and the (now invisible, alpha-0) window would linger in
    // -[NSApp orderedWindows] forever. That stray ordered window makes AppKit believe iTerm2 still
    // has a visible window after the last terminal closes, so a Dock-icon reopen never triggers
    // -applicationOpenUntitledFile: and no new terminal window opens (issue 12996). -orderOut: is
    // what actually removes it from the ordered-window list.
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        window.animator.alphaValue = 0;
    } completionHandler:^{
        [window orderOut:nil];
        [window release];
    }];
}

- (AXUIElementRef)downloadsMenuElement {
    return [self menuElementWithAXIdentifier:iTermDownloadsMenuAXIdentifier];
}

- (AXUIElementRef)uploadsMenuElement {
    return [self menuElementWithAXIdentifier:iTermUploadsMenuAXIdentifier];
}

// Find a top-level menu bar element by its accessibility identifier. We match on the
// identifier rather than the title because titles are localizable but identifiers are not,
// so this keeps working when the menu bar is translated.
- (AXUIElementRef)menuElementWithAXIdentifier:(NSString *)identifier {
    AXUIElementRef appElement = AXUIElementCreateApplication(getpid());
    AXUIElementRef menuBar;
    AXError error = AXUIElementCopyAttributeValue(appElement,
                                                  kAXMenuBarAttribute,
                                                  (CFTypeRef *)&menuBar);
    CFRelease(appElement);
    if (error) {
        return NULL;
    }

	CFIndex count = -1;
	error = AXUIElementGetAttributeValueCount(menuBar, kAXChildrenAttribute, &count);
    if (error) {
        CFRelease(menuBar);
        return NULL;
    }

	NSArray *children = nil;
    // Despite what the name would suggest, the children array and its contents don't seen to need
    // too be released by us.
	error = AXUIElementCopyAttributeValues(menuBar,
                                           kAXChildrenAttribute,
                                           0,
                                           count,
                                           (CFArrayRef *)&children);
    if (error) {
        CFRelease(menuBar);
        return NULL;
    }

    for (id child in children) {
        AXUIElementRef element = (AXUIElementRef)child;
        id elementIdentifier;
        error = AXUIElementCopyAttributeValue(element,
                                              kAXIdentifierAttribute,
                                              (CFTypeRef *)&elementIdentifier);
        if (error) {
            continue;
        }
        BOOL found = [elementIdentifier isEqualToString:identifier];
        CFRelease(elementIdentifier);
        if (found) {
            return element;
        }
    }

    DLog(@"No menu bar element found with accessibility identifier %@", identifier);
    return NULL;
}

- (void)openDownloadsMenu {
    AXUIElementRef menuElement = [self downloadsMenuElement];
    if (menuElement) {
        AXUIElementPerformAction(menuElement, kAXPressAction);
        CFRelease(menuElement);
    }
}

- (void)openUploadsMenu {
    AXUIElementRef menuElement = [self uploadsMenuElement];
    if (menuElement) {
        AXUIElementPerformAction(menuElement, kAXPressAction);
        CFRelease(menuElement);
    }
}

- (void)removeAllDownloads {
    NSArray *removableStatuses = @[ @(kTransferrableFileStatusFinishedSuccessfully),
                                    @(kTransferrableFileStatusFinishedWithError),
                                    @(kTransferrableFileStatusCancelled) ];

    NSArray *downloads = [_viewControllers filteredArrayUsingBlock:^BOOL(TransferrableFileMenuItemViewController *anObject) {
        return anObject.transferrableFile.isDownloading && [removableStatuses containsObject:@(anObject.transferrableFile.status)];
    }];
    for (TransferrableFileMenuItemViewController *controller in downloads) {
        [self removeItem:controller];
    }
}

- (void)removeAllUploads {
    NSArray *removableStatuses = @[ @(kTransferrableFileStatusFinishedSuccessfully),
                                    @(kTransferrableFileStatusFinishedWithError),
                                    @(kTransferrableFileStatusCancelled) ];
    NSArray *downloads = [_viewControllers filteredArrayUsingBlock:^BOOL(TransferrableFileMenuItemViewController *anObject) {
        return !anObject.transferrableFile.isDownloading && [removableStatuses containsObject:@(anObject.transferrableFile.status)];
    }];
    for (TransferrableFileMenuItemViewController *controller in downloads) {
        [self removeItem:controller];
    }
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
    NSMenuItem *subItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"FileTransfer.Stop", nil, [NSBundle mainBundle], @"Stop", @"Menu item to stop an in-progress transfer")
                                                      action:@selector(stop:)
                                               keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.stopSubItem = subItem;

    if (transferrableFile.isDownloading) {
        subItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"FileTransfer.ShowInFinder", nil, [NSBundle mainBundle], @"Show in Finder", @"Menu item to reveal a downloaded file in Finder")
                                              action:@selector(showInFinder:)
                                       keyEquivalent:@""] autorelease];
        [subItem setTarget:controller];
        [submenu addItem:subItem];
        controller.showInFinderSubItem = subItem;
    }

    subItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"FileTransfer.RemoveFromList", nil, [NSBundle mainBundle], @"Remove from List", @"Menu item to remove a transfer from the transfers list")
                                          action:@selector(removeFromList:)
                                   keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.removeFromListSubItem = subItem;

    if (transferrableFile.isDownloading) {
        subItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"General.Open", nil, [NSBundle mainBundle], @"Open", @"Open button")
                                              action:@selector(open:)
                                       keyEquivalent:@""] autorelease];
        [subItem setTarget:controller];
        [submenu addItem:subItem];
        controller.openSubItem = subItem;
    }

    subItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"FileTransfer.GetInfo", nil, [NSBundle mainBundle], @"Get Info", @"Menu item to show information about a transferred file")
                                          action:@selector(getInfo:)
                                   keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.openSubItem = subItem;

    item.submenu = submenu;

    [controller update];
    return item;
}

- (NSMenu *)menuForFile:(TransferrableFile *)transferrableFile {
    if (transferrableFile.isDownloading) {
        return [self downloadsMenu];
    } else {
        return [self uploadsMenu];
    }
}

- (void)transferrableFileDidStartTransfer:(TransferrableFile *)transferrableFile {
    RLog(@"Transfer started");
    [[self menuForFile:transferrableFile] addItem:[self menuItemForTransferrableFile:transferrableFile]];
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

// Number of bytes transferred has changed or total size has been discovered.
- (void)transferrableFileProgressDidChange:(TransferrableFile *)transferrableFile {
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

// |error| is nil on success
- (void)transferrableFile:(TransferrableFile *)transferrableFile
    didFinishTransmissionWithError:(NSError *)error {
    if (error) {
        [transferrableFile didFailWithError:error.localizedDescription ?: NSLocalizedStringWithDefaultValue(@"FileTransfer.UnknownError", nil, [NSBundle mainBundle], @"File transfer failed with an unknown error", @"Error shown when a file transfer fails without a specific reason")];
    } else {
        transferrableFile.status = kTransferrableFileStatusFinishedSuccessfully;
    }
    RLog(@"Transfer finished. error=%@", error);

    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];

    // Call the completion block if set
    if (transferrableFile.completionBlock) {
        BOOL success = (error == nil);
        NSString *errorMessage = error.localizedDescription;
        transferrableFile.completionBlock(success, errorMessage);
        transferrableFile.completionBlock = nil;  // Clear to avoid retain cycles
    }
}

- (void)transferrableFileWillStop:(TransferrableFile *)transferrableFile {
    RLog(@"file transfer stop requested");
    transferrableFile.status = kTransferrableFileStatusCancelling;
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];
}

- (void)transferrableFileDidStopTransfer:(TransferrableFile *)transferrableFile {
    RLog(@"file transfer stopped");
    transferrableFile.status = kTransferrableFileStatusCancelled;
    TransferrableFileMenuItemViewController *controller = [self viewControllerForTransferrableFile:transferrableFile];
    [controller update];

    // Call the completion block if set (transfer was cancelled)
    if (transferrableFile.completionBlock) {
        transferrableFile.completionBlock(NO, NSLocalizedStringWithDefaultValue(@"FileTransfer.TransferCancelled", nil, [NSBundle mainBundle], @"Transfer cancelled", @"Message reported when a file transfer was cancelled"));
        transferrableFile.completionBlock = nil;
    }
}


// Shows a modal alert with the text in |prompt| and a freeform keyboard input. Returns the
// value entered.
- (void)transferrableFile:(TransferrableFile *)transferrableFile
        interactivePrompt:(NSString *)prompt
               completion:(void (^)(NSString *password))completion {
    NSString *text = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"FileTransfer.AuthenticateTitle", nil, [NSBundle mainBundle], @"Authenticate %@", @"Title of the authentication dialog; %@ is who is requesting authentication"), transferrableFile.authRequestor];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = text;
    alert.informativeText = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"FileTransfer.AuthPrompt", nil, [NSBundle mainBundle], @"Please enter the %1$@ for %2$@ to begin %3$@.", @"Prompt asking for a credential; first %@ is the credential type (e.g. password), second %@ is who is requesting it, third %@ is the operation name"),
                             prompt, transferrableFile.authRequestor,
                             transferrableFile.protocolName];
    [alert addButtonWithTitle:iTermLocalizedOK()];
    [alert addButtonWithTitle:iTermLocalizedCancel()];
    [alert addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"FileTransfer.PasswordManager", nil, [NSBundle mainBundle], @"Password Manager…", @"Button to open the password manager to fill in credentials")];

    NSSecureTextField *input =
        [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    [alert layout];
    [[alert window] makeFirstResponder:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [input validateEditing];
        completion([input stringValue]);
    } else if (button == NSAlertThirdButtonReturn) {
        [self asynchronouslySelectPasswordFromPasswordManager:completion];
    } else {
        completion(nil);
    }
}

- (void)asynchronouslySelectPasswordFromPasswordManager:(void (^)(NSString *password))completion {
    if (_passwordManagerWindowController) {
        completion(nil);
        return;
    }
    _passwordManagerWindowController = [[iTermPasswordManagerWindowController alloc] init];
    _passwordManagerWindowController.delegate = self;
    [[_passwordManagerWindowController window] makeKeyAndOrderFront:nil];
    _passwordCompletion = [completion copy];
}

// Shows message, returns YES if OK, NO if Cancel
- (BOOL)transferrableFile:(TransferrableFile *)transferrableFile
                    title:(NSString *)title
           confirmMessage:(NSString *)message {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:iTermLocalizedOK()];
    [alert addButtonWithTitle:iTermLocalizedCancel()];

    [alert layout];
    NSInteger button = [alert runModal];
    return (button == NSAlertFirstButtonReturn);
}

- (void)removeItem:(TransferrableFileMenuItemViewController *)viewController {
    NSMenuItem *item = [viewController.view enclosingMenuItem];
    [[item menu] removeItem:item];
    [_viewControllers removeObject:viewController];
}

#pragma mark - iTermPasswordManagerDelegate

- (BOOL)iTermPasswordManagerCanEnterPassword {
    return YES;
}

- (void)iTermPasswordManagerEnterPassword:(NSString *)password broadcast:(BOOL)broadcast {
    if (_passwordCompletion) {
        _passwordCompletion(password);
    }
    _passwordCompletion = nil;
    _passwordManagerWindowController.delegate = nil;
    _passwordManagerWindowController = nil;
}

- (void)iTermPasswordManagerEnterUserName:(NSString *)username broadcast:(BOOL)broadcast {
    assert(false);
}

- (BOOL)iTermPasswordManagerCanEnterUserName {
    return NO;
}

- (BOOL)iTermPasswordManagerCanBroadcast {
    return NO;
}

- (void)iTermPasswordManagerDidClose {
    _passwordCompletion = nil;
    _passwordManagerWindowController.delegate = nil;
    _passwordManagerWindowController = nil;
}

@end
