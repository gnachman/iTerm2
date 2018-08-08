//
//  iTermMenuBarObserver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/8/18.
//

#import "iTermMenuBarObserver.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import <Carbon/Carbon.h>

static const NSTimeInterval iTermMenuBarObserverDelay = 0.01;
static const CGFloat iTermMenuBarHeight = 22;

@interface iTermMenuBarObserver()
- (void)menuBarVisibilityDidChangeWithEvent:(EventRef)event;
@end

OSErr menuBarVisibilityChangedCallback(EventHandlerCallRef inHandlerRef, EventRef inEvent, void *userData) {
    iTermMenuBarObserver *observer = (__bridge iTermMenuBarObserver *)userData;
    [observer menuBarVisibilityDidChangeWithEvent:inEvent];
    return noErr;
}

@implementation iTermMenuBarObserver {
    BOOL _fullscreenMode;
    BOOL _menuBarVisible;  // This is YES when in a desktop with a full screen app that isn't us.
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        EventTypeSpec events[] = {
            { kEventClassMenu, kEventMenuBarShown },
            { kEventClassMenu, kEventMenuBarHidden }
        };
        _menuBarVisible = [NSMenu menuBarVisible];
        InstallEventHandler(GetEventDispatcherTarget(),
                            NewEventHandlerUPP((EventHandlerProcPtr)menuBarVisibilityChangedCallback),
                            2,
                            events,
                            (__bridge void *)(self), nil);

        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChangeNotification:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
    }

    return self;
}

- (BOOL)menuBarVisible {
    return _menuBarVisible && !self.currentDesktopHasFullScreenWindow;
}

#pragma mark - Private

- (void)scheduleCheck {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(iTermMenuBarObserverDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self checkForFullScreenChange:nil];
    });
}

- (void)activeSpaceDidChangeNotification:(NSNotification *)notification {
    [self scheduleCheck];
    DLog(@"Activate space changed. set menu bar visible to %@", @([NSMenu menuBarVisible]));
    _menuBarVisible = [NSMenu menuBarVisible];
}

- (void)menuBarVisibilityDidChangeWithEvent:(EventRef)event {
    _menuBarVisible = (GetEventKind(event) != kEventMenuBarHidden);
    DLog(@"Menu bar visibility did change with event. set menu bar visible to %@", @(GetEventKind(event) != kEventMenuBarHidden));
    [self scheduleCheck];
}

- (void)checkForFullScreenChange:(NSTimer *)timer {
    if (([self menuBarOffScreen] && [self isMenuBarAttachedToMainScreen])) {
        _currentDesktopHasFullScreenWindow = YES;
    } else {
        _currentDesktopHasFullScreenWindow = NO;
    }
}

- (BOOL)isMenuBarAttachedToMainScreen {
    return [[NSScreen mainScreen] isEqualTo:self.screenWithMenuBar];
}

- (NSScreen *)screenWithMenuBar {
    return [[NSScreen screens] firstObject];
}

- (NSArray<NSDictionary *> *)allWindowInfoDictionaries {
    const CGWindowListOption options = (kCGWindowListExcludeDesktopElements |
                                        kCGWindowListOptionOnScreenOnly);
    NSArray<NSDictionary *> *windowInfos = (__bridge NSArray *)CGWindowListCopyWindowInfo(options,
                                                                                          kCGNullWindowID);
    return windowInfos;
}

- (NSDictionary *)menuBarWindowInfoDictionary {
    NSArray<NSDictionary *> *windowInfos = self.allWindowInfoDictionaries;
    NSDictionary *menuBarWindowInfo = [windowInfos objectPassingTest:^BOOL(NSDictionary *info, NSUInteger index, BOOL *stop) {
        NSString *windowName = info[(id)kCGWindowName];
        return [windowName isEqualToString:@"Menubar"];
    }];
    return menuBarWindowInfo;
}

- (CGRect)windowBoundsRectFromWindowInfoDictionary:(NSDictionary *)dictionary {
    CGRect rect = CGRectMake(NAN, NAN, 0, 0);
    BOOL ok = NO;
    if (dictionary) {
        ok = CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)dictionary[(id)kCGWindowBounds],
                                                    &rect);
    }
    if (!ok) {
        rect = CGRectMake(NAN, NAN, 0, 0);
    }
    return rect;
}

- (CGRect)actualMenuBarFrame {
    NSDictionary *menuBarWindowInfo = [self menuBarWindowInfoDictionary];
    CGRect windowBounds =  [self windowBoundsRectFromWindowInfoDictionary:menuBarWindowInfo];
    return windowBounds;
}

- (CGRect)expectedFrameOfVisibleMenuBar {
    CGRect menuBarFrame = [self.screenWithMenuBar frame];
    menuBarFrame.size.height = iTermMenuBarHeight;
    return menuBarFrame;
}

- (BOOL)menuBarOffScreen {
    const BOOL menuBarOnScreen = CGRectContainsPoint(self.expectedFrameOfVisibleMenuBar,
                                                     self.actualMenuBarFrame.origin);
    return !menuBarOnScreen;
}

@end
