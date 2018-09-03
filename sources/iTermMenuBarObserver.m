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

static const CGFloat iTermMenuBarHeight = 22;

@implementation iTermMenuBarObserver {
    BOOL _fullscreenMode;
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
        DLog(@"Initialize menu bar observer");
    }

    return self;
}

- (BOOL)menuBarVisibleOnScreen:(NSScreen *)screen {
    return [[self screensWithMenuBars] containsObject:screen];
}

#pragma mark - Private

- (NSArray<NSDictionary *> *)allWindowInfoDictionaries {
    const CGWindowListOption options = (kCGWindowListExcludeDesktopElements |
                                        kCGWindowListOptionOnScreenOnly);
    NSArray<NSDictionary *> *windowInfos = (__bridge NSArray *)CGWindowListCopyWindowInfo(options,
                                                                                          kCGNullWindowID);
    return windowInfos;
}

- (NSArray<NSDictionary *> *)menuBarWindowInfoDictionaries {
    NSArray<NSDictionary *> *windowInfos = self.allWindowInfoDictionaries;
    NSArray<NSDictionary *> *menuBarInfos = [windowInfos filteredArrayUsingBlock:^BOOL(NSDictionary *info) {
        NSString *windowName = info[(id)kCGWindowName];
        return [windowName isEqualToString:@"Menubar"];
    }];
    DLog(@"menu bar infos:\n%@", menuBarInfos);
    return menuBarInfos;
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

- (NSArray<NSValue *> *)actualMenuBarFrames {
    NSArray<NSDictionary *> *menuBarWindowInfos = [self menuBarWindowInfoDictionaries];
    return [menuBarWindowInfos mapWithBlock:^id(NSDictionary *info) {
        CGRect windowBounds =  [self windowBoundsRectFromWindowInfoDictionary:info];
        return [NSValue valueWithRect:windowBounds];
    }];
}

- (CGRect)expectedFrameOfVisibleMenuBarOnScreen:(NSScreen *)screenWithMenuBar {
    CGRect menuBarFrame = screenWithMenuBar.frame;
    CGRect firstScreenFrame = [[[NSScreen screens] firstObject] frame];
    // Menu bar frames are flipped versus screen frames, and are relative to the first screen.
    // A menu bar y coordinate of 0 equals the top of the first screen.
    // A screen y coordinate of 0 equals the bottom of the first screen.
    menuBarFrame.origin.y = firstScreenFrame.size.height - screenWithMenuBar.frame.size.height - screenWithMenuBar.frame.origin.y;
    menuBarFrame.size.height = iTermMenuBarHeight;
    return menuBarFrame;
}

- (NSArray<NSScreen *> *)screensWithMenuBars {
    NSArray<NSValue *> *actualFrames = [self actualMenuBarFrames];
    NSArray<NSScreen *> *screens = [NSScreen screens];
    NSArray<NSScreen *> *screensWithMenuBars = [screens filteredArrayUsingBlock:^BOOL(NSScreen *screen) {
        CGRect expectedFrame = [self expectedFrameOfVisibleMenuBarOnScreen:screen];
        return [actualFrames anyWithBlock:^BOOL(NSValue *value) {
            const NSRect actualMenuBarFrame = value.rectValue;
            return CGRectContainsPoint(expectedFrame,
                                       actualMenuBarFrame.origin);
        }];
    }];
    DLog(@"Screens with menu bars are %@ from all screens %@", screensWithMenuBars, screens);
    return screensWithMenuBars;
}

@end
