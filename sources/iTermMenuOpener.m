//
//  iTermMenuOpener.m
//  iTerm2
//
//  Created by George Nachman on 3/6/17.
//
//

#import "iTermMenuOpener.h"

#import "DebugLogging.h"
#import "iTermHelpMessageViewController.h"
#import "NSArray+iTerm.h"

@interface iTermMenuOpener()<NSMenuDelegate>
@end

@implementation iTermMenuOpener {
    NSPopover *_popover;
    NSMenu *_menu;
    NSWindow *_window;
    iTermMenuOpener *_self;
}

+ (void)revealMenuWithPath:(NSArray<NSString *> *)path
                   message:(NSString *)message {
    iTermMenuOpener *menuOpener = [[iTermMenuOpener alloc] init];
    [menuOpener revealMenuWithPath:path message:message];
}

- (void)revealMenuWithPath:(NSArray<NSString *> *)path
                   message:(NSString *)message {
    NSArray *elements = [self elementsToMenuWithPath:path];
    if (elements == nil) {
        return;
    }
    DLog(@"Revealing menu with path %@", path);

    NSMenu *menu = [NSApp mainMenu];
    NSMenuItem *item = nil;
    for (NSString *name in path) {
        item = [menu.itemArray objectPassingTest:^BOOL(NSMenuItem *element, NSUInteger index, BOOL *stop) {
            return [element.title isEqualToString:name];
        }];
        if (name != path.lastObject) {
            menu = item.submenu;
        }
    }
    if (!menu || !item) {
        DLog(@"Failed to find menu item.");
        return;
    }

    _menu.delegate = nil;
    _menu = menu;
    menu.delegate = self;

    [self clickThroughElements:elements completion:^{
        if (self->_menu.delegate == self) {
            DLog(@"Done clicking through elements.");
            DLog(@"Menu is %@, item is %@", menu, item);
            NSRect frame = [self frameOfElement:(__bridge AXUIElementRef)(elements.lastObject)];
            [self showMessage:message byFrame:frame menuItem:item];
        } else {
            DLog(@"Delegate is no longer self");
        }
    }];
}

#pragma mark - Private

- (NSRect)frameOfElement:(AXUIElementRef)element {
    CFTypeRef temp;
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &temp);

    CGPoint position;
    AXValueGetValue(temp, kAXValueCGPointType, &position);

    AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &temp);

    CGSize size;
    AXValueGetValue(temp, kAXValueCGSizeType, &size);

    return NSMakeRect(position.x, position.y, size.width, size.height);
}

- (void)showMessage:(NSString *)message byFrame:(NSRect)frame menuItem:(NSMenuItem *)item {
    DLog(@"Opening window and popover at %@", NSStringFromRect(frame));
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSZeroRect
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    window.contentView = view;
    window.level = NSPopUpMenuWindowLevel;
    window.alphaValue = 0;
    NSRect screen = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect windowFrame = NSMakeRect(frame.origin.x + screen.origin.x, NSMaxY(screen) - NSMaxY(frame), frame.size.width, frame.size.height);
    [window setFrame:windowFrame display:YES];
    [window makeKeyAndOrderFront:nil];
    window.releasedWhenClosed = NO;
    _window = window;

    // Create view controller
    iTermHelpMessageViewController *viewController = [[iTermHelpMessageViewController alloc] initWithNibName:@"iTermHelpMessageViewController"
                                                                                                      bundle:[NSBundle mainBundle]];
    [viewController setMessage:message];

    // Create popover
    NSPopover *popover = [[NSPopover alloc] init];
    popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    [popover setContentSize:viewController.view.frame.size];
    [popover setBehavior:NSPopoverBehaviorTransient];
    [popover setAnimates:YES];
    [popover setContentViewController:viewController];

    // Show popover
    [popover showRelativeToRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                              ofView:window.contentView
                       preferredEdge:NSMinYEdge];
    _popover = popover;

    // Keep myself from getting dealloc'ed until the window is released.
    _self = self;
}

- (void)clickThroughElements:(NSArray *)elements completion:(void(^)(void))completion {
    if (_menu.delegate != self) {
        DLog(@"I'm not the menu's delegate. We must have been canceled.");
        return;
    }
    if (elements.count == 0) {
        DLog(@"No elements, wtf");
        completion();
        return;
    }
    AXUIElementRef element = (__bridge AXUIElementRef)elements.firstObject;

    if (elements.count > 1) {
        [self openMenuElement:element];
        DLog(@"Schedule next click...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self clickThroughElements:[elements subarrayFromIndex:1] completion:completion];
        });
    } else {
        DLog(@"Done clicking through elements");
        completion();
    }
}

- (NSArray *)elementsToMenuWithPath:(NSArray<NSString *> *)path {
    NSMutableArray *result = [NSMutableArray array];
    AXUIElementRef element = [self menuBar];
    NSInteger i = 0;
    while (element != nil && i < path.count) {
        element = [self childOfMenu:element withName:path[i]];
        [result addObject:(__bridge id _Nonnull)(element)];
        i++;
        if (i < path.count) {
            element = [self submenuOfMenu:element];
        }
    }
    if (i != path.count) {
        return nil;
    } else {
        return result;
    }
}

- (AXUIElementRef)menuBar {
    AXUIElementRef appElement = AXUIElementCreateApplication(getpid());
    AXUIElementRef menuBar;
    AXError error = AXUIElementCopyAttributeValue(appElement,
                                                  kAXMenuBarAttribute,
                                                  (CFTypeRef *)&menuBar);
    if (error) {
        return NULL;
    }
    return menuBar;
}

- (NSArray *)childrenOfMenu:(AXUIElementRef)menuBar {
    CFIndex count = -1;
    AXError error = AXUIElementGetAttributeValueCount(menuBar, kAXChildrenAttribute, &count);

    CFArrayRef children = nil;
    // Despite what the name would suggest, the children array and its contents don't seen to need
    // too be released by us.
    error = AXUIElementCopyAttributeValues(menuBar,
                                           kAXChildrenAttribute,
                                           0,
                                           count,
                                           &children);
    if (error) {
        return NULL;
    }

    return (__bridge NSArray *)children;
}

- (NSString *)titleOfMenu:(AXUIElementRef)element {
    CFTypeRef title;
    AXError error = AXUIElementCopyAttributeValue(element,
                                                  kAXTitleAttribute,
                                                  &title);
    if (error) {
        return nil;
    }
    return (__bridge NSString *)title;
}

- (AXUIElementRef)childOfMenu:(AXUIElementRef)menuBar withName:(NSString *)menuName {
    for (id child in [self childrenOfMenu:menuBar]) {
        AXUIElementRef element = (__bridge AXUIElementRef)child;
        NSString *title = [self titleOfMenu:element];
        if ([title isEqualToString:menuName]) {
            return element;
        }
    }

    return NULL;
}

- (AXUIElementRef)submenuOfMenu:(AXUIElementRef)menu {
    return (__bridge AXUIElementRef)([[self childrenOfMenu:menu] firstObject]);
}

- (void)openMenuElement:(AXUIElementRef)menuElement {
    AXUIElementPerformAction(menuElement, kAXPressAction);
}

- (void)closePopover {
    DLog(@"Close popover");
    _menu.delegate = nil;
    if (_popover) {
        [_popover close];
        _popover = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_window close];
            self->_window = nil;
            self->_self = nil;
        });
    } else {
        [_window close];
        _window = nil;
        _self = nil;
    }
}

#pragma mark - NSMenuDelegate

- (void)menuDidClose:(NSMenu *)menu {
    DLog(@"menuDidClose");
    [self closePopover];
}

- (void)menu:(NSMenu *)menu willHighlightItem:(nullable NSMenuItem *)item {
    DLog(@"willHighlightItem");
    if (_popover) {
        [self closePopover];
    }
}

@end
