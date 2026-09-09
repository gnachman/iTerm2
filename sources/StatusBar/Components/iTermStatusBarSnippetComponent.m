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

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconSnippet" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return NSLocalizedStringWithDefaultValue(@"StatusBarSnippet.ShortDescription", nil, [NSBundle mainBundle], @"Snippets Menu", @"Short description of the snippets menu status bar component");
}

- (NSString *)statusBarComponentDetailedDescription {
    return NSLocalizedStringWithDefaultValue(@"StatusBarSnippet.DetailedDescription", nil, [NSBundle mainBundle], @"When clicked, opens a menu of snippets. Snippets are saved text strings that can be pasted quickly.", @"Detailed description of the snippets menu status bar component");
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return NSLocalizedStringWithDefaultValue(@"StatusBarSnippet.Exemplar", nil, [NSBundle mainBundle], @"Snippet…", @"Exemplar shown in the status bar component picker for the snippets menu component");
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return NSLocalizedStringWithDefaultValue(@"StatusBarSnippet.StringValue", nil, [NSBundle mainBundle], @"Send Snippet…", @"Label shown in the status bar for the snippets menu component");
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ];
}

- (NSString *)statusBarComponentCopyableString {
    return nil;
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

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"StatusBarSnippet.EditSnippets", nil, [NSBundle mainBundle], @"Edit Snippets…", @"Menu item to open the snippets editor") action:@selector(editSnippets:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];

    [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
}

- (void)editSnippets:(id)sender {
    [self.delegate statusBarComponentEditSnippets:self];
}

@end
