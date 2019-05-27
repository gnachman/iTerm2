//
//  iTermOnboardingWindowController.m
//  iTerm2
//
//  Created by George Nachman on 1/13/19.
//

#import "iTermOnboardingWindowController.h"

#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "PTYSession.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "SessionView.h"

static NSString *const iTermOnboardingWindowControllerHasBeenShown = @"NoSyncOnboardingWindowHasBeenShown";

static void iTermTryMinimalCompact(NSWindow *window) {
    const iTermPreferencesTabStyle savedTabStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    [iTermPreferences setInt:TAB_STYLE_MINIMAL forKey:kPreferenceKeyTabStyle];
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification
                                                        object:nil
                                                      userInfo:nil];
    PTYSession *session = [[iTermController sharedInstance] launchBookmark:nil
                                                                inTerminal:nil
                                                        respectTabbingMode:NO];
    [session.view.window performZoom:nil];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Minimal Theme"];
    [alert setInformativeText:@"The theme has been changed to minimal. Want to keep it?"];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Undo"];
    [alert setAlertStyle:NSAlertStyleInformational];

    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            return;
        };
        [iTermPreferences setInt:savedTabStyle forKey:kPreferenceKeyTabStyle];
        [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification
                                                            object:nil
                                                          userInfo:nil];
    }];
}

static void iTermTryStatusBar(NSWindow *window) {
    ProfileModel *model = [ProfileModel sharedInstance];
    Profile *profile = [model defaultBookmark];
    [iTermProfilePreferences setBool:YES forKey:KEY_SHOW_STATUS_BAR inProfile:profile model:model];
    [[PreferencePanel sharedInstance] openToProfileWithGuid:[[model defaultBookmark] objectForKey:KEY_GUID]
                             andEditComponentWithIdentifier:nil
                                                       tmux:NO
                                                      scope:nil];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Status Bar"];
    [alert setInformativeText:@"The status bar setup panel has been opened, and the status bar is now enabled for your default profile. Add some components by dragging them to the bottom section to try it out."];
    [alert addButtonWithTitle:@"OK"];
    [alert setAlertStyle:NSAlertStyleInformational];

    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
    }];
}

static void iTermTrySessionTitles() {
    ProfileModel *model = [ProfileModel sharedInstance];
    [[PreferencePanel sharedInstance] openToProfileWithGuid:[[model defaultBookmark] objectForKey:KEY_GUID]
                                           selectGeneralTab:YES
                                                       tmux:NO
                                                      scope:nil];
}

static void iTermOpenWhatsNewURL(NSString *path, NSWindow *window) {
    if ([path isEqualToString:@"/minimal-compact"]) {
        iTermTryMinimalCompact(window);
        return;
    }
    if ([path isEqualToString:@"/statusbar"]) {
        iTermTryStatusBar(window);
    }

    if ([path isEqualToString:@"/session-titles"]) {
        iTermTrySessionTitles();
    }
}

@interface iTermOnboardingView : NSView
@end

@implementation iTermOnboardingView

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor textBackgroundColor] set];
    NSRectFill(dirtyRect);
}

@end

@interface iTermOnboardingTextField : NSTextField
@end

@implementation iTermOnboardingTextField

// For some stupid reason links aren't clickable in this window. It's probably
// because of the type of panel. I don't feel light spending hours fighting
// with Cocoa's undocumented insolence so let's just route around the damage.
- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self.attributedStringValue];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:self.bounds.size];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];

    NSInteger index = [layoutManager characterIndexForPoint:point inTextContainer:textContainer fractionOfDistanceBetweenInsertionPoints:nil];
    if (index >= 0 && index < self.attributedStringValue.length) {
        NSDictionary *attributes = [self.attributedStringValue attributesAtIndex:index effectiveRange:nil];
        NSURL *url = attributes[NSLinkAttributeName];
        if (url) {
            if ([url.scheme isEqualToString:@"iterm2whatsnew"]) {
                iTermOpenWhatsNewURL(url.path, self.window);
            } else {
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
            return;
        }
    }
    [super mouseUp:event];
}
@end

@interface iTermOnboardingWindowController ()<NSPageControllerDelegate, NSTextViewDelegate>

@end

@implementation iTermOnboardingWindowController {
    IBOutlet NSPageController *_pageController;
    IBOutlet NSView *_view1;
    IBOutlet NSView *_view2;
    IBOutlet NSView *_view3;
    IBOutlet NSView *_view4;

    IBOutlet NSButton *_pageIndicator1;
    IBOutlet NSButton *_pageIndicator2;
    IBOutlet NSButton *_pageIndicator3;
    IBOutlet NSButton *_pageIndicator4;

    NSArray<NSView *> *_views;
    NSArray<NSView *> *_pageIndicators;
    IBOutlet NSButton *_previousPageButton;
    IBOutlet NSButton *_nextPageButton;

    IBOutlet NSTextField *_textField1;
    IBOutlet NSTextField *_textField2;
    IBOutlet NSTextField *_textField3;
    IBOutlet NSTextField *_textField4;
}

+ (BOOL)hasBeenShown {
    return [[NSUserDefaults standardUserDefaults] boolForKey:iTermOnboardingWindowControllerHasBeenShown];
}

+ (void)suppressFutureShowings {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:iTermOnboardingWindowControllerHasBeenShown];
}

+ (BOOL)previousLaunchVersionImpliesShouldBeShown {
    NSString *lastVersion = [iTermPreferences appVersionBeforeThisLaunch];
    if (!lastVersion) {
        return NO;
    }
    NSArray<NSString *> *parts = [lastVersion componentsSeparatedByString:@"."];
    if (parts.count < 2) {
        return NO;
    }
    NSString *twoPartVersion = [[parts subarrayWithRange:NSMakeRange(0, 2)] componentsJoinedByString:@"."];
    NSArray<NSString *> *versionsForAnnouncement = @[ @"3.1", @"3.2" ];
    return [versionsForAnnouncement containsObject:twoPartVersion];
}

+ (BOOL)shouldBeShown {
    if ([self hasBeenShown]) {
        return NO;
    }
    return YES;
}

- (void)awakeFromNib {
    NSMutableAttributedString *attributedString;
    // LOL the IB setting is not respected in 10.12 so you have to do it in code.
    self.window.titlebarAppearsTransparent = YES;
    if (@available(macOS 10.14, *)) {
        NSString *url1 = @"iterm2whatsnew:/minimal-compact";
        NSMutableAttributedString *attributedString = _textField1.attributedStringValue.mutableCopy;
        [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url1 title:@"Try it now!"]];
        _textField1.attributedStringValue = attributedString;
    } else {
        _textField1.stringValue = [_textField1.stringValue stringByAppendingString:@"Available on macOS 10.14."];
    }

    NSString *url2 = @"iterm2whatsnew:/statusbar";
    attributedString = _textField2.attributedStringValue.mutableCopy;
    [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url2 title:@"Try it now!"]];
    _textField2.attributedStringValue = attributedString;

    NSString *url3 = @"iterm2whatsnew:/session-titles";
    attributedString = _textField3.attributedStringValue.mutableCopy;
    [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url3 title:@"Try it now!"]];
    _textField3.attributedStringValue = attributedString;

    NSString *url4 = @"https://iterm2.com/python-api";
    attributedString = _textField4.attributedStringValue.mutableCopy;
    [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url4 title:@"Learn more."]];
    _textField4.attributedStringValue = attributedString;

    _views = @[ [self wrap:_view1], [self wrap:_view2], [self wrap:_view3], [self wrap:_view4] ];
    _pageIndicators = @[ _pageIndicator1, _pageIndicator2, _pageIndicator3, _pageIndicator4 ];
    _pageController.arrangedObjects = @[ @0, @1, @2, @3 ];
    _pageController.transitionStyle = NSPageControllerTransitionStyleStackBook;
    _previousPageButton.alphaValue = 0;
    _nextPageButton.alphaValue = 0;
    for (NSView *view in _pageIndicators) {
        view.alphaValue = 0.25;
    }
    [self updateButtons];
    [self.class suppressFutureShowings];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[NSAttributedString alloc] initWithString:localizedTitle
                                           attributes:linkAttributes];
}

- (IBAction)previousPage:(id)sender {
    [_pageController navigateBack:nil];
}

- (IBAction)nextPage:(id)sender {
    [_pageController navigateForward:nil];
}

- (NSView *)wrap:(NSView *)view {
    const CGFloat margin = 50;
    NSView *wrapper = [[iTermOnboardingView alloc] initWithFrame:NSMakeRect(0, 0, view.frame.size.width + margin * 2, view.frame.size.height)];
    [wrapper addSubview:view];
    view.frame = NSMakeRect(margin, 0, view.frame.size.width, view.frame.size.height);
    return wrapper;
}

- (void)updateButtons {
    const CGFloat maxAlpha = 0.5;
    if (_pageController.selectedIndex == 0) {
        _previousPageButton.animator.alphaValue = 0;
    } else {
        _previousPageButton.animator.alphaValue = maxAlpha;
    }
    if (_pageController.selectedIndex + 1 == _views.count) {
        _nextPageButton.animator.alphaValue = 0;
    } else {
        _nextPageButton.animator.alphaValue = maxAlpha;
    }
    for (NSInteger i = 0; i < _pageIndicators.count; i++) {
        _pageIndicators[i].animator.alphaValue = i == _pageController.selectedIndex ? maxAlpha : 0.25;
    }
}

- (IBAction)pageIndicator:(id)sender {
    NSInteger index = [_pageIndicators indexOfObject:sender];
    if (index != NSNotFound) {
        if (index > _pageController.selectedIndex) {
            [_pageController navigateForward:nil];
            return;
        }
        if (index < _pageController.selectedIndex) {
            [_pageController navigateBack:nil];
            return;
        }
    }
}

#pragma mark - NSPageControllerDelegate

- (void)pageController:(NSPageController *)pageController didTransitionToObject:(id)object {
    [self updateButtons];
}

- (NSString *)pageController:(NSPageController *)pageController identifierForObject:(id)object {
    return [object stringValue];
}

- (NSViewController *)pageController:(NSPageController *)pageController viewControllerForIdentifier:(NSString *)identifier {
    NSInteger index = [identifier integerValue];
    NSViewController *viewController = [[NSViewController alloc] init];
    NSView *view = _views[index];
    viewController.view = view;
    return viewController;
}

@end
