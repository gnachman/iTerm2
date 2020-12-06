//
//  iTermStatusBarActionComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import "iTermStatusBarActionComponent.h"
#import "iTermActionsModel.h"
#import "iTermScriptHistory.h"
#import "iTermSwiftyString.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "RegexKitLite.h"

static NSString *const iTermStatusBarActionKey = @"action";

@implementation iTermStatusBarActionComponent {
    NSString *_value;
    iTermSwiftyString *_swiftyString;
}

- (nullable NSArray<NSString *> *)stringVariants {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    [_value enumerateStringsSeparatedByRegex:@"\\h+"
                                     options:RKLNoOptions
                                     inRange:NSMakeRange(0, _value.length)
                                       error:nil
                          enumerationOptions:RKLRegexEnumerationNoOptions
                                  usingBlock:
     ^(NSInteger captureCount,
       NSString *const __unsafe_unretained *capturedStrings,
       const NSRange *capturedRanges,
       volatile BOOL *const stop) {

        [result addObject:[self->_value substringToIndex:NSMaxRange(capturedRanges[0])]];
    }];
    return result;
}

- (void)setStringValue:(NSString *)value {
    _value = [value copy];
    [self updateTextFieldIfNeeded];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *actionKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Action"
                                                      type:iTermStatusBarComponentKnobTypeAction
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarActionKey];
    return [@[ actionKnob, [super statusBarComponentKnobs] ] flattenedArray];
}

- (NSDictionary *)actionDictionary {
    return self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarActionKey];
}

- (iTermAction *)action {
    return [[iTermAction alloc] initWithDictionary:self.actionDictionary];
}

- (void)updateTitleInButton {
    if (_swiftyString) {
        _swiftyString.swiftyString = self.action.title;
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSString *expression = self.action.title.copy ?: @"";
    _swiftyString = [[iTermSwiftyString alloc] initWithString:expression
                                                        scope:self.scope
                                                     observer:^(NSString * _Nonnull newValue, NSError *error) {
        if (error != nil) {
            [[iTermScriptHistoryEntry globalEntry] addOutput:[NSString stringWithFormat:@"Error while evaluating %@ in status bar action button: %@", expression, error]
                                                  completion:^{}];
            return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
        }
        [weakSelf setStringValue:newValue];
        return newValue;
    }];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Custom Action";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds a button that performs a user-configurable action, similar to a key binding.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    NSDictionary *dict = self.actionDictionary;
    if (dict.count) {
        return self.action.title;
    } else {
        return @"Custom Action";
    }
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate>)delegate {
    [super setDelegate:delegate];
    [self updateTitleInButton];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (BOOL)statusBarComponentIsEmpty {
    return NO;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    if (self.actionDictionary) {
        [self.delegate statusBarComponentPerformAction:self.action];
    }
}

@end

@implementation iTermStatusBarActionMenuComponent

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Actions Menu";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"When clicked, opens a menu of actions. Actions are like custom key bindings, but without a keystroke attached.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"Action…";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return @"Perform Action…";
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
    return [[[iTermActionsModel sharedInstance] actions] count] == 0;
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
    for (iTermAction *action in [[iTermActionsModel sharedInstance] actions]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:action.title action:@selector(performAction:) keyEquivalent:@""];
        item.identifier = [@(action.identifier) stringValue];
        item.target = self;
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Edit Actions…" action:@selector(editActions:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];

    [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
}

- (void)performAction:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        return;
    }
    iTermAction *action = [[iTermActionsModel sharedInstance] actionWithIdentifier:[menuItem.identifier integerValue]];
    if (!action) {
        return;
    }
    [self.delegate statusBarComponentPerformAction:action];
}

- (void)editActions:(id)sender {
    [self.delegate statusBarComponentEditActions:self];
}

@end
