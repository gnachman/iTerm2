//
//  iTermOnboardingWindowController.m
//  iTerm2
//
//  Created by George Nachman on 1/13/19.
//

#import "iTermOnboardingWindowController.h"

#import "ITAddressBookMgr.h"
#import "iTermClickableTextField.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermSessionLauncher.h"
#import "PTYSession.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "SessionView.h"

static NSString *const iTermOnboardingWindowControllerHasBeenShown = @"NoSyncOnboardingWindowHasBeenShown34";

static void iTermOpenWhatsNewURL(NSString *path, NSWindow *window) {
//    if ([path isEqualToString:@"/foo"]) {
//        iTermTryFoo(window);
//        return;
//    }
}

@interface iTermOnboardingView : NSView
@end

@implementation iTermOnboardingView

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    [[NSColor textBackgroundColor] set];
    NSRectFill(dirtyRect);
}

@end

// For some stupid reason links aren't clickable in this window. It's probably
// because of the type of panel. I don't feel light spending hours fighting
// with Cocoa's undocumented insolence so let's just route around the damage.
@interface iTermOnboardingTextField : iTermClickableTextField
@end

@implementation iTermOnboardingTextField

- (void)openURL:(NSURL *)url {
    if ([url.scheme isEqualToString:@"iterm2whatsnew"]) {
        iTermOpenWhatsNewURL(url.path, self.window);
        return;
    }
    [super openURL:url];
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
    NSArray<NSString *> *versionsForAnnouncement = @[ @"3.1", @"3.2", @"3.3", @"3.4" ];
    return [versionsForAnnouncement containsObject:twoPartVersion];
}

+ (BOOL)shouldBeShown {
    if ([self hasBeenShown]) {
        return NO;
    }
    return YES;
}

- (void)awakeFromNib {
    // LOL the IB setting is not respected in 10.12 so you have to do it in code.
    self.window.titlebarAppearsTransparent = YES;

    // This is the place to tweak the contents of text fields for conditionally available features
    // or to add hyperlinks. None needed in 3.4, but maybe the next version will want them.
    // Also look at the commit history to see how it was done for 3.3.

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
