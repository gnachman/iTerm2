//
//  iTermStatusBarComposerComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarComposerComponent.h"

#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermShellHistoryController.h"
#import "iTermsStatusBarComposerViewController.h"
#import "iTermVariableScope.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "PTYSession.h"
#import "VT100RemoteHost.h"

@interface iTermStatusBarComposerComponent() <iTermsStatusBarComposerViewControllerDelegate>
@end

@implementation iTermStatusBarComposerComponent {
    iTermsStatusBarComposerViewController *_viewController;
}

- (void)makeFirstResponder {
    [[self viewController] makeFirstResponder];
}

- (void)deselect {
    [[self viewController] deselect];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *textColorKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Icon Color:"
                                                      type:iTermStatusBarComponentKnobTypeColor
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarSharedTextColorKey];
    iTermStatusBarComponentKnob *backgroundColorKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color:"
                                                      type:iTermStatusBarComponentKnobTypeColor
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarSharedBackgroundColorKey];

    return [@[ textColorKnob, backgroundColorKnob, [super statusBarComponentKnobs], [self minMaxWidthKnobs] ] flattenedArray];
}

- (CGFloat)statusBarComponentPreferredWidth {
    return INFINITY;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    NSRect frame = view.frame;
    frame.size.width = width;
    view.frame = frame;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 200;
}

- (NSString *)statusBarComponentShortDescription {
    return @"Composer";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds a text field for composing command lines.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @">_ [Command] 💬";
}

- (iTermsStatusBarComposerViewController *)viewController {
    if (!_viewController) {
        _viewController = [[iTermsStatusBarComposerViewController alloc] initWithNibName:@"iTermsStatusBarComposerViewController" bundle:[NSBundle bundleForClass:self.class]];
        _viewController.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(commandHistoryDidChange:)
                                                     name:kCommandHistoryDidChangeNotificationName
                                                   object:nil];
        // Give the session a chance to finish initializing and then reload data.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_viewController reloadData];
        });
    }
    return _viewController;
}

- (PTYSession *)session {
    NSString *sessionID = [self.scope valueForVariableName:iTermVariableKeySessionID];
    return [[iTermController sharedInstance] sessionWithGUID:sessionID];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithObject:iTermVariableKeySessionHostname];
}

- (NSString *)stringValue {
    return [[self viewController] stringValue];
}

- (void)insertText:(NSString *)text {
    [self.viewController insertText:text];
}

- (void)setStringValue:(NSString *)stringValue {
    [[self viewController] setStringValue:stringValue];
}

- (NSRect)cursorFrameInScreenCoordinates {
    return [[self viewController] cursorFrameInScreenCoordinates];
}

#pragma mark - iTermStatusBarComponent

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconComposer" forClass:[self class]];
}

- (NSView *)statusBarComponentView {
    [self updateForTerminalBackgroundColor];

    VT100RemoteHost *remoteHost = [[VT100RemoteHost alloc] initWithUsername:[self.scope valueForVariableName:iTermVariableKeySessionUsername]
                                                                   hostname:[self.scope valueForVariableName:iTermVariableKeySessionHostname]];

    [self.viewController setHost:remoteHost];
    return self.viewController.view;
}

- (void)statusBarTerminalBackgroundColorDidChange {
    [self updateForTerminalBackgroundColor];
}

- (void)updateForTerminalBackgroundColor {
    NSView *view = self.viewController.view;
    const iTermPreferencesTabStyle tabStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (tabStyle == TAB_STYLE_MINIMAL) {
        if ([self.delegate statusBarComponentTerminalBackgroundColorIsDark:self]) {
            view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        } else {
            view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        }
    } else {
        view.appearance = nil;
    }
}

- (nullable NSColor *)statusBarTextColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedTextColorKey] colorValue] ?: ([self defaultTextColor] ?: [self.delegate statusBarComponentDefaultTextColor]);
}

- (void)statusBarDefaultTextColorDidChange {
    _viewController.tintColor = [self statusBarTextColor];
}

#pragma mark - iTermsStatusBarComposerViewControllerDelegate

- (void)statusBarComposer:(iTermsStatusBarComposerViewController *)composer
              sendCommand:(NSString *)command {
    [self.session writeTask:[command stringByAppendingString:@"\n"]];
}

- (NSArray<NSString *> *)statusBarComposerSuggestions:(iTermsStatusBarComposerViewController *)composer {
    NSArray<NSString *> *commands = [[[[self.session commandUses] mapWithBlock:^id(iTermCommandHistoryCommandUseMO *anObject) {
        return anObject.command;
    }] reverseObjectEnumerator] allObjects];
    return commands;
}

- (NSFont *)statusBarComposerFont:(iTermsStatusBarComposerViewController *)composer {
    return [self.delegate statusBarComponentTerminalFont:self];
}

- (BOOL)statusBarComposerShouldForceDarkAppearance:(iTermsStatusBarComposerViewController *)composer {
    return [self.delegate statusBarComponentTerminalBackgroundColorIsDark:self];
}

- (void)statusBarComposerDidEndEditing:(iTermsStatusBarComposerViewController *)composer {
    if (self.composerDelegate) {
        [self.composerDelegate statusBarComposerComponentDidEndEditing:self];
    } else {
        [self.delegate statusBarComponentResignFirstResponder:self];
    }
}

- (void)statusBarComposerRevealComposer:(iTermsStatusBarComposerViewController *)composer {
    [self.delegate statusBarComponentComposerRevealComposer:self];
}
#pragma mark - Notifications

- (void)commandHistoryDidChange:(NSNotification *)notification {
    // TODO: This is not very efficient.
    [_viewController reloadData];
}

@end
