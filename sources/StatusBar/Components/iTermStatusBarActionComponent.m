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
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:NSLocalizedStringWithDefaultValue(@"StatusBarAction.ActionKnobLabel", nil, [NSBundle mainBundle], @"Action", @"Label for the action knob in the custom action status bar component")
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
                                           sideEffectsAllowed:false
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
    return NSLocalizedStringWithDefaultValue(@"StatusBarAction.CustomAction", nil, [NSBundle mainBundle], @"Custom Action", @"Name of the custom action status bar component");
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSString *)statusBarComponentDetailedDescription {
    return NSLocalizedStringWithDefaultValue(@"StatusBarAction.DetailedDescription", nil, [NSBundle mainBundle], @"Adds a button that performs a user-configurable action, similar to a key binding.", @"Detailed description of the custom action status bar component");
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    NSDictionary *dict = self.actionDictionary;
    if (dict.count) {
        return self.action.title;
    } else {
        return NSLocalizedStringWithDefaultValue(@"StatusBarAction.CustomAction", nil, [NSBundle mainBundle], @"Custom Action", @"Name of the custom action status bar component");
    }
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate> _Nullable)delegate {
    [super setDelegate:delegate];
    [self updateTitleInButton];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (NSString *)statusBarComponentCopyableString {
    return nil;
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

- (NSString *)statusBarComponentCopyableString {
    return nil;
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconAction" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return NSLocalizedStringWithDefaultValue(@"StatusBarAction.MenuShortDescription", nil, [NSBundle mainBundle], @"Actions Menu", @"Short description of the actions menu status bar component");
}

- (NSString *)statusBarComponentDetailedDescription {
    return NSLocalizedStringWithDefaultValue(@"StatusBarAction.MenuDetailedDescription", nil, [NSBundle mainBundle], @"When clicked, opens a menu of actions. Actions are like custom key bindings, but without a keystroke attached.", @"Detailed description of the actions menu status bar component");
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return NSLocalizedStringWithDefaultValue(@"StatusBarAction.MenuExemplar", nil, [NSBundle mainBundle], @"Action…", @"Exemplar shown in the status bar component picker for the actions menu component");
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return NSLocalizedStringWithDefaultValue(@"StatusBarAction.MenuStringValue", nil, [NSBundle mainBundle], @"Perform Action…", @"Label shown in the status bar for the actions menu component");
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

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"StatusBarAction.EditActions", nil, [NSBundle mainBundle], @"Edit Actions…", @"Menu item to open the actions editor") action:@selector(editActions:) keyEquivalent:@""];
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
