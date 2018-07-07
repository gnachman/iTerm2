/*
 **  iTermNotificationController.m
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for Growl notifications.
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
#import "iTermController.h"
#import "iTermAdvancedSettingsModel.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

#import <Growl/Growl.h>

static NSString *const kGrowlAppName = @"iTerm";
static NSString *const kDefaultNotification = @"Miscellaneous";

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
        NSBundle *myBundle = [NSBundle bundleForClass:[iTermNotificationController class]];
        NSString *growlPath =
            [[myBundle privateFrameworksPath] stringByAppendingPathComponent:@"Growl.framework"];
        NSBundle *growlBundle = [NSBundle bundleWithPath:growlPath];
        if (growlBundle && [growlBundle load]) {
            // Register ourselves as a Growl delegate
            [GrowlApplicationBridge setGrowlDelegate:self];
        } else {
            NSLog(@"Could not load Growl.framework");
        }

        [self registrationDictionaryForGrowl];
        
        // Register as delegate for notification center
        [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    }
    return self;
}

- (void)notify:(NSString *)title {
    [self notify:title withDescription:nil];
}

- (void)notify:(NSString *)title
     withDescription:(NSString *)description {
    [self notify:title
      withDescription:description
      andNotification:kDefaultNotification];
}

- (void)notify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification {
      [self notify:title
        withDescription:description
        andNotification:notification
            windowIndex:-1
               tabIndex:-1
              viewIndex:-1];
}

- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex {
    return [self notify:title
             withDescription:description
             andNotification:notification
                 windowIndex:windowIndex
                    tabIndex:tabIndex
                   viewIndex:viewIndex
                      sticky:NO];
}

- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex
             sticky:(BOOL)sticky {
    DLog(@"Notify title=%@ description=%@ notification=%@ window=%@ tab=%@ view=%@ sticky=%@",
         title, description, notification, @(windowIndex), @(tabIndex), @(viewIndex), @(sticky));
    NSDictionary *context = nil;
    if (windowIndex >= 0) {
        context = @{ @"win": @(windowIndex),
                     @"tab": @(tabIndex),
                     @"view": @(viewIndex) };
    }

    if ([iTermAdvancedSettingsModel disableGrowl]) {
        // Send to NSUserDefaults directly
        // The (BOOL)sticky parameter is ignored
        NSUserNotification *notification = [[[NSUserNotification alloc] init] autorelease];
        notification.title = title;
        notification.informativeText = description;
        notification.userInfo = context;
        notification.soundName = NSUserNotificationDefaultSoundName;
        DLog(@"Post notification %@", notification);
        [[NSUserNotificationCenter defaultUserNotificationCenter]
            deliverNotification:notification];
    } else {
        DLog(@"Post to growl");
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:description
                               notificationName:notification
                                       iconData:nil
                                       priority:0
                                       isSticky:sticky
                                   clickContext:context];
    }

    return YES;
}

- (void)growlNotificationWasClicked:(id)clickContext {
    DLog(@"growlNotificationWasClicked");
    [self notificationWasClicked:clickContext];
}

- (void)notificationWasClicked:(id)clickContext {
    DLog(@"notificationWasClicked:%@", clickContext);
    int win = [clickContext[@"win"] intValue];
    int tab = [clickContext[@"tab"] intValue];
    int view = [clickContext[@"view"] intValue];

    iTermController *controller = [iTermController sharedInstance];
    if (win >= [controller numberOfTerminals]) {
        DLog(@"bogus window number");
        NSBeep();
        return;
    }
    PseudoTerminal *terminal = [controller terminalAtIndex:win];
    DLog(@"window controller is %@", terminal);
    PTYTabView *tabView = [terminal tabView];
    if (tab >= [tabView numberOfTabViewItems]) {
        DLog(@"bogus tab");
        NSBeep();
        return;
    }
    PTYTab *theTab = [[tabView tabViewItemAtIndex:tab] identifier];
    DLog(@"tab is %@", theTab);
    PTYSession *theSession = [theTab sessionWithViewId:view];
    DLog(@"Reveal %@", theSession);
    [theSession reveal];
}

- (NSDictionary *)registrationDictionaryForGrowl {
    NSArray *notifications = @[ @"Bells",
                                @"Broken Pipes",
                                @"Miscellaneous",
                                @"Idle",
                                @"New Output",
                                @"Customized Message",
                                @"Mark Set" ];
    return @{ GROWL_APP_NAME: kGrowlAppName,
              GROWL_NOTIFICATIONS_ALL: notifications,
              GROWL_NOTIFICATIONS_DEFAULT: notifications };
}

- (void)growlIsReady {
    NSLog(@"Growl is ready");
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
