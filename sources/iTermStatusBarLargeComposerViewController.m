//
//  iTermStatusBarLargeComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarLargeComposerViewController.h"

#import "CommandHistoryPopup.h"
#import "NSEvent+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSView+iTerm.h"
#import "SolidColorView.h"
#import "iTermPopupWindowController.h"
#import "iTermShellHistoryController.h"
#import "iTermWarning.h"
#import "WindowControllerInterface.h"

@interface iTermComposerView : NSView
@end

@implementation iTermComposerTextView

- (BOOL)it_preferredFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    const BOOL pressedEsc = ([event.characters isEqualToString:@"\x1b"]);
    const BOOL pressedShiftEnter = ([event.characters isEqualToString:@"\r"] &&
                                    (event.it_modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift);
    if (pressedShiftEnter || pressedEsc) {
        [self.composerDelegate composerTextViewDidFinishWithCancel:pressedEsc];
        return;
    }
    [super keyDown:event];
}

- (BOOL)resignFirstResponder {
    if ([self.composerDelegate respondsToSelector:@selector(composerTextViewDidResignFirstResponder)]) {
        [self.composerDelegate composerTextViewDidResignFirstResponder];
    }
    return [super resignFirstResponder];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        self.continuousSpellCheckingEnabled = NO;
        self.grammarCheckingEnabled = NO;
        self.automaticLinkDetectionEnabled = NO;
        self.automaticQuoteSubstitutionEnabled = NO;
        self.automaticDashSubstitutionEnabled = NO;
        self.automaticDataDetectionEnabled = NO;
        self.automaticTextReplacementEnabled = NO;
        self.smartInsertDeleteEnabled = NO;
    }
    return self;
}
@end

@implementation iTermComposerView {
    NSView *_backgroundView;
}

- (NSView *)newBackgroundViewWithFrame:(NSRect)frame {
    if (@available(macOS 10.14, *)) {
        NSVisualEffectView *myView = [[NSVisualEffectView alloc] initWithFrame:frame];
        myView.appearance = self.appearance;
        return myView;
    }

    SolidColorView *solidColorView = [[SolidColorView alloc] initWithFrame:frame
                                                                     color:[NSColor controlBackgroundColor]];
    return solidColorView;
}

- (void )viewDidMoveToWindow {
    [self updateBackgroundView];
    [super viewDidMoveToWindow];
}

- (void)updateBackgroundView {
    if ([NSStringFromClass(self.window.class) containsString:@"Popover"]) {
        NSView *privateView = [[self.window contentView] superview];
        [_backgroundView removeFromSuperview];
        _backgroundView = [self newBackgroundViewWithFrame:privateView.bounds];
        _backgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [privateView addSubview:_backgroundView positioned:NSWindowBelow relativeTo:privateView];
    }
}

- (void)setAppearance:(NSAppearance *)appearance {
    if (appearance != self.appearance) {
        [super setAppearance:appearance];
        [self updateBackgroundView];
    }
}
@end

@interface iTermStatusBarLargeComposerViewController ()<PopupDelegate, iTermPopupWindowPresenter, NSTextViewDelegate>

@end

@implementation iTermStatusBarLargeComposerViewController {
    IBOutlet NSButton *_help;
    CommandHistoryPopupWindowController *_historyWindowController;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.textView.textColor = [NSColor textColor];
    self.textView.font = [NSFont fontWithName:@"Menlo" size:11];
}

- (void)viewWillLayout {
    _help.enabled = [self helpShouldBeAvailable];
    [super viewWillLayout];
}

- (NSString *)commandAtCursor {
    NSString *content = self.textView.string;
    const NSRange selectedRange = [self.textView selectedRange];
    if (selectedRange.location > content.length) {
        return @"";
    }

    NSInteger lowerBound = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                       options:NSBackwardsSearch
                                                         range:NSMakeRange(0, selectedRange.location)].location;
    if (lowerBound == NSNotFound) {
        lowerBound = 0;
    } else {
        lowerBound += 1;
    }
    NSInteger upperBound = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                    options:0
                                                      range:NSMakeRange(lowerBound, content.length - lowerBound)].location;
    if (upperBound == NSNotFound) {
        upperBound = content.length;
    }
    return [content substringWithRange:NSMakeRange(lowerBound, upperBound - lowerBound)];
}

- (void)openCommandHistory:(id)sender {
    if (!_historyWindowController) {
        _historyWindowController = [[CommandHistoryPopupWindowController alloc] initForAutoComplete:NO];
    }
    if ([[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        NSString *prefix;
        NSString *content = self.textView.string;
        const NSRange selectedRange = [self.textView selectedRange];
        if (selectedRange.location > content.length) {
            return;
        }
        const NSInteger newlineBefore = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                                 options:NSBackwardsSearch
                                                                   range:NSMakeRange(0, selectedRange.location)].location;
        if (newlineBefore == NSNotFound) {
            prefix = [content substringToIndex:selectedRange.location];
        } else {
            prefix = [content substringWithRange:NSMakeRange(newlineBefore + 1, selectedRange.location - newlineBefore - 1)];
        }
        [_historyWindowController popWithDelegate:self inWindow:self.view.window];
        [_historyWindowController loadCommands:[_historyWindowController commandsForHost:self.host
                                                                          partialCommand:prefix
                                                                                  expand:YES]
                                partialCommand:prefix];
    } else {
        [iTermShellHistoryController showInformationalMessage];
    }
}

- (BOOL)helpShouldBeAvailable {
    return [[self commandAtCursor] length] > 0 && [[self browserName] length] > 0;
}

- (NSString *)browserName {
    NSURL *appUrl = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:[NSURL URLWithString:@"https://explainshell.com/explain?cmd=example"]];
    if (!appUrl) {
        return nil;
    }
    NSBundle *bundle = [NSBundle bundleWithURL:appUrl];
    return [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: [[appUrl URLByDeletingPathExtension] lastPathComponent];
}

- (IBAction)help:(id)sender {
    NSString *command = [self commandAtCursor];
    if (!command.length) {
        return;
    }
    NSString *browserName = [self browserName];
    if (!browserName.length) {
        return;
    }
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.host = @"explainshell.com";
    components.scheme = @"https";
    components.path = @"/explain";
    components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"cmd" value:command] ];
    NSURL *url = components.URL;

    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"This will open %@ in %@.", url.absoluteString, browserName]
                                                                       actions:@[ @"OK", @"Cancel" ]
                                                                 actionMapping:nil
                                                                     accessory:nil
                                                                    identifier:@"NoSyncExplainShell"
                                                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                                                       heading:@"Open ExplainShell?"
                                                                        window:self.view.window];
    if (selection == kiTermWarningSelection0) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}


#pragma mark - PopupDelegate

- (NSRect)popupScreenVisibleFrame {
    return self.view.window.screen.visibleFrame;
}

- (VT100Screen *)popupVT100Screen {
    return nil;
}

- (id<iTermPopupWindowPresenter>)popupPresenter {
    return self;
}

- (void)popupInsertText:(NSString *)text {
    [self.textView insertText:text replacementRange:self.textView.selectedRange];
}

- (void)popupKeyDown:(NSEvent *)event {
    [self.textView keyDown:event];
}

- (BOOL)popupHandleSelector:(SEL)selector string:(NSString *)string currentValue:(NSString *)currentValue {
    return NO;
}

- (void)popupWillClose:(iTermPopupWindowController *)popup {
    _historyWindowController = nil;
}

- (BOOL)popupWindowIsInFloatingHotkeyWindow {
    id<iTermWindowController> windowController = (id<iTermWindowController>)self.view.window.delegate;
    if ([windowController conformsToProtocol:@protocol(iTermWindowController)]) {
        return [windowController isFloatingHotKeyWindow];
    }
    return NO;
}

- (void)popupIsSearching:(BOOL)searching {
}

#pragma mark - iTermPopupWindowPresenter

- (void)popupWindowWillPresent:(iTermPopupWindowController *)popupWindowController {
}

- (NSRect)popupWindowOriginRectInScreenCoords {
    NSRange range = [self.textView selectedRange];
    range.length = 0;
    return [self.textView firstRectForCharacterRange:range actualRange:NULL];
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)notification {
    _help.enabled = [self helpShouldBeAvailable];
}

@end
