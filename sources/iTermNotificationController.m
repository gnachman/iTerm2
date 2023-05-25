/*
 **  iTermNotificationController.m
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for notifications.
 **               See iTermNotificationController.h for usage information.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermNotificationController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermImage.h"
#import "iTermAdvancedSettingsModel.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

@interface iTermNotificationController ()
- (void)notificationWasClicked:(id)clickContext;
@end

@implementation iTermNotificationController

+ (id)sharedInstance {
    static iTermNotificationController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Register as delegate for notification center
        [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    }
    return self;
}

- (void)notify:(NSString *)title {
    [self notify:title withDescription:nil];
}

- (void)notify:(NSString *)title withDescription:(NSString *)description {
      [self notify:title
        withDescription:description
            windowIndex:-1
               tabIndex:-1
              viewIndex:-1];
}

- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex {
    return [self notify:title
             withDescription:description
                 windowIndex:windowIndex
                    tabIndex:tabIndex
                   viewIndex:viewIndex
                      sticky:NO];
}

- (BOOL)notifyRich:(NSString *)title
      withSubtitle:(NSString *)subtitle
   withDescription:(NSString *)description
         withImage:(NSString *)image
       windowIndex:(int)windowIndex
          tabIndex:(int)tabIndex
         viewIndex:(int)viewIndex {
    DLog(@"Notify title=%@ description=%@ window=%@ tab=%@ view=%@",
            title, description, @(windowIndex), @(tabIndex), @(viewIndex));

    if (description == nil) {
        DLog(@"notifyRich passed nil description.");
        return NO;
    }

    // Send to NSUserDefaults directly
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.informativeText = description;

    NSDictionary *context = nil;
    if (windowIndex >= 0) {
        context = @{ @"win": @(windowIndex),
                     @"tab": @(tabIndex),
                     @"view": @(viewIndex) };
    }
    notification.userInfo = context;

    if (title != nil) {
        notification.title = title;
    }
    if (subtitle != nil) {
        notification.subtitle = subtitle;
    }
    if (image != nil) {
        NSData *data = [NSData dataWithContentsOfFile:image];
        if (data != nil) {
            notification.contentImage = [[[iTermImage imageWithCompressedData:data] images] firstObject];
        }
    }
    DLog(@"Post notification %@", notification);
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

    return [notification isPresented];
}

- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex
             sticky:(BOOL)sticky {
    DLog(@"Notify title=%@ description=%@ window=%@ tab=%@ view=%@ sticky=%@",
         title, description, @(windowIndex), @(tabIndex), @(viewIndex), @(sticky));
    NSDictionary *context = nil;
    if (windowIndex >= 0) {
        context = @{ @"win": @(windowIndex),
                     @"tab": @(tabIndex),
                     @"view": @(viewIndex) };
    }

    // Send to NSUserDefaults directly
    // The (BOOL)sticky parameter is ignored
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = title;
    notification.informativeText = description;
    notification.userInfo = context;
    notification.soundName = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : NSUserNotificationDefaultSoundName;
    DLog(@"Post notification %@", notification);
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

    return YES;
}

- (void)postNotificationWithTitle:(NSString *)title detail:(NSString *)detail URL:(NSURL *)url {
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = title;
    notification.informativeText = detail;
    NSDictionary *context = @{ @"URL": url.absoluteString };
    notification.userInfo = context;
    notification.soundName = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : NSUserNotificationDefaultSoundName;
    DLog(@"Post notification %@", notification);
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void)postNotificationWithTitle:(NSString *)title
                           detail:(NSString *)detail
         callbackNotificationName:(NSString *)name
     callbackNotificationUserInfo:(NSDictionary *)userInfo {
    [self postNotificationWithTitle:title detail:detail callbackNotificationName:name callbackNotificationUserInfo:userInfo actionButtonTitle:nil];
}

- (void)postNotificationWithTitle:(NSString *)title
                           detail:(NSString *)detail
         callbackNotificationName:(NSString *)name
     callbackNotificationUserInfo:(NSDictionary *)userInfo
                actionButtonTitle:(NSString *)actionButtonTitle {
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = title;
    notification.informativeText = detail;
    NSDictionary *context = @{ @"CallbackNotificationName": name,
                               @"CallbackUserInfo": userInfo ?: @{} };
    notification.userInfo = context;
    notification.soundName = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : NSUserNotificationDefaultSoundName;
    if (actionButtonTitle) {
        notification.actionButtonTitle = actionButtonTitle;
    }
    DLog(@"Post notification %@", notification);
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}


- (void)notificationWasClicked:(id)clickContext {
    DLog(@"notificationWasClicked:%@", clickContext);

    NSString *callbackName = clickContext[@"CallbackNotificationName"];
    NSDictionary *callbackUserInfo = clickContext[@"CallbackUserInfo"];
    if (callbackName && callbackUserInfo) {
        [[NSNotificationCenter defaultCenter] postNotificationName:callbackName object:nil userInfo:callbackUserInfo];
        return;
    }

    NSURL *url = [NSURL URLWithString:clickContext[@"URL"]];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    int win = [clickContext[@"win"] intValue];
    int tab = [clickContext[@"tab"] intValue];
    int view = [clickContext[@"view"] intValue];

    iTermController *controller = [iTermController sharedInstance];
    if (win >= [controller numberOfTerminals]) {
        DLog(@"Beep: bogus window number");
        NSBeep();
        return;
    }
    PseudoTerminal *terminal = [controller terminalAtIndex:win];
    DLog(@"window controller is %@", terminal);
    PTYTabView *tabView = [terminal tabView];
    if (tab >= [tabView numberOfTabViewItems]) {
        DLog(@"Beep: bogus tab");
        NSBeep();
        return;
    }
    PTYTab *theTab = [[tabView tabViewItemAtIndex:tab] identifier];
    DLog(@"tab is %@", theTab);
    PTYSession *theSession = [theTab sessionWithViewId:view];
    DLog(@"Reveal %@", theSession);
    [theSession reveal];
}

#pragma mark Notifications Delegate Methods

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    [self notificationWasClicked:notification.userInfo];
    [center removeDeliveredNotification:notification];
}

@end
