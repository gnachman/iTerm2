//
//  iTermStatusBarSnippetComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/9/20.
//

#import "iTermStatusBarSnippetComponent.h"
#import "iTermSnippetsMenuController.h"
#import "iTermSnippetsModel.h"
#import "iTermScriptHistory.h"
#import "iTermSwiftyString.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "RegexKitLite.h"

@implementation iTermStatusBarSnippetMenuComponent

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconSnippet" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Snippets Menu";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"When clicked, opens a menu of snippets. Snippets are saved text strings that can be pasted quickly.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"Snippet…";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return @"Send Snippet…";
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ];
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (BOOL)statusBarComponentIsEmpty {
    return [[[iTermSnippetsModel sharedInstance] snippets] count] == 0;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (BOOL)statusBarComponentHandlesMouseDown {
    return YES;
}

- (void)openMenuWithView:(NSView *)view {
    NSView *containingView = view.superview;

    NSMenu *menu = [[NSMenu alloc] init];
    iTermSnippetsMenuController *menuController = [[iTermSnippetsMenuController alloc] init];
    menuController.menu = menu;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Edit Snippets…" action:@selector(editSnippets:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];

    [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
}

- (void)editSnippets:(id)sender {
    [self.delegate statusBarComponentEditSnippets:self];
}

@end
