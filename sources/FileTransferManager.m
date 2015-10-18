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

// Finished downloads will be automatically removed from the downloads menu after this number of
// seconds.
static const NSTimeInterval kMaximumTimeToKeepFinishedDownload = 24 * 60 * 60;

@interface FileTransferManager ()
@property(nonatomic, retain) NSMutableArray *files;
@end

@implementation FileTransferManager {
    NSMutableArray *_viewControllers;
    NSTimer *_timer;  // cleanUpMenus timer. weak reference.
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
    iTermApplicationDelegate *ad = (iTermApplicationDelegate *)[[NSApplication sharedApplication] delegate];
    return [ad downloadsMenu];
}

- (NSMenu *)uploadsMenu {
    iTermApplicationDelegate *ad = (iTermApplicationDelegate *)[[NSApplication sharedApplication] delegate];
    return [ad uploadsMenu];
}

- (void)animateImage:(NSImage *)image
            intoMenu:(AXUIElementRef)menuElement
           fromPoint:(NSPoint)point
            onScreen:(NSScreen *)screen {
    if (menuElement) {
        CFTypeRef temp;
        AXUIElementCopyAttributeValue(menuElement, kAXPositionAttribute, (CFTypeRef *)&temp);

        CGPoint position;
        AXValueGetValue(temp, kAXValueCGPointType, &position);
        CFRelease(temp);
        CFRelease(menuElement);
        
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(point.x,
                                                                            point.y,
                                                                            image.size.width,
                                                                            image.size.height)
                                                       styleMask:NSBorderlessWindowMask
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
}

- (void)animateImage:(NSImage *)image intoDownloadsMenuFromPoint:(NSPoint)point onScreen:(NSScreen *)screen {
    AXUIElementRef menuElement = [self downloadsMenuElement];
    [self animateImage:image intoMenu:menuElement fromPoint:point onScreen:screen];
}

- (void)fadeWindowOut:(NSWindow *)window {
    [window.animator setAlphaValue:0];
    [window performSelector:@selector(release)
               withObject:nil
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (AXUIElementRef)downloadsMenuElement {
    return [self menuElementNamed:@"Downloads"];
}

- (AXUIElementRef)uploadsMenuElement {
    return [self menuElementNamed:@"Uploads"];
}

- (AXUIElementRef)menuElementNamed:(NSString *)menuName {
    AXUIElementRef appElement = AXUIElementCreateApplication(getpid());
    AXUIElementRef menuBar;
    AXError error = AXUIElementCopyAttributeValue(appElement,
                                                  kAXMenuBarAttribute,
                                                  (CFTypeRef *)&menuBar);
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
        id title;
        error = AXUIElementCopyAttributeValue(element,
                                              kAXTitleAttribute,
                                              (CFTypeRef *)&title);
        if (error) {
            continue;
        }
        BOOL found = [title isEqualToString:menuName];
        CFRelease(title);
        if (found) {
            return element;
        }
    }
    
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
    
    if (transferrableFile.isDownloading) {
        subItem = [[[NSMenuItem alloc] initWithTitle:@"Show in Finder"
                                              action:@selector(showInFinder:)
                                       keyEquivalent:@""] autorelease];
        [subItem setTarget:controller];
        [submenu addItem:subItem];
        controller.showInFinderSubItem = subItem;
    }
    
    subItem = [[[NSMenuItem alloc] initWithTitle:@"Remove from List"
                                          action:@selector(removeFromList:)
                                   keyEquivalent:@""] autorelease];
    [subItem setTarget:controller];
    [submenu addItem:subItem];
    controller.removeFromListSubItem = subItem;

    if (transferrableFile.isDownloading) {
        subItem = [[[NSMenuItem alloc] initWithTitle:@"Open"
                                              action:@selector(open:)
                                       keyEquivalent:@""] autorelease];
        [subItem setTarget:controller];
        [submenu addItem:subItem];
        controller.openSubItem = subItem;
    }

    subItem = [[[NSMenuItem alloc] initWithTitle:@"Get Info"
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
    NSLog(@"Transfer started");
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
    transferrableFile.status = error ? kTransferrableFileStatusFinishedWithError : kTransferrableFileStatusFinishedSuccessfully;
    NSLog(@"Transfer finished. error=%@", error);

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
    NSString *text = [NSString stringWithFormat:@"Authenticate %@", transferrableFile.authRequestor];
    NSAlert *alert = [NSAlert alertWithMessageText:text
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Please enter the %@ for %@ to begin %@.",
                                                       prompt, transferrableFile.authRequestor,
                                                       transferrableFile.protocolName];
    
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
                    title:(NSString *)title
           confirmMessage:(NSString *)message {
    NSAlert *alert = [NSAlert alertWithMessageText:title
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"%@", message];
    
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
