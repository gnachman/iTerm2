/*
 **  iTermGrowlDelegate.m
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for Growl notifications.
 **               See iTermGrowlDelegate.h for usage information.
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

#import "iTermGrowlDelegate.h"

#import "iTermController.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

#import <Growl/Growl.h>

static NSString *const kGrowlAppName = @"iTerm";
static NSString *const kDefaultNotification = @"Miscellaneous";

@implementation iTermGrowlDelegate

+ (id)sharedInstance {
    static iTermGrowlDelegate *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSBundle *myBundle = [NSBundle bundleForClass:[iTermGrowlDelegate class]];
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
    }
    return self;
}

- (void)growlNotify:(NSString *)title {
    [self growlNotify:title withDescription:nil];
}

- (void)growlNotify:(NSString *)title
     withDescription:(NSString *)description {
    [self growlNotify:title
      withDescription:description
      andNotification:kDefaultNotification];
}

- (void)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification {
      [self growlNotify:title
        withDescription:description
        andNotification:notification
            windowIndex:-1
               tabIndex:-1
              viewIndex:-1];
}

- (BOOL)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex {
    return [self growlNotify:title
             withDescription:description
             andNotification:notification
                 windowIndex:windowIndex
                    tabIndex:tabIndex
                   viewIndex:viewIndex
                      sticky:NO];
}

- (BOOL)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex
             sticky:(BOOL)sticky {
    NSDictionary *context = nil;
    if (windowIndex >= 0) {
        context = @{ @"win": @(windowIndex),
                     @"tab": @(tabIndex),
                     @"view": @(viewIndex) };
    }

    [GrowlApplicationBridge notifyWithTitle:title
                                description:description
                           notificationName:notification
                                   iconData:nil
                                   priority:0
                                   isSticky:sticky
                               clickContext:context];
    return YES;
}

- (void)growlNotificationWasClicked:(id)clickContext {
    int win = [clickContext[@"win"] intValue];
    int tab = [clickContext[@"tab"] intValue];
    int view = [clickContext[@"view"] intValue];

    iTermController *controller = [iTermController sharedInstance];
    if (win >= [controller numberOfTerminals]) {
        NSBeep();
        return;
    }
    PseudoTerminal *terminal = [controller terminalAtIndex:win];
    PTYTabView *tabView = [terminal tabView];
    if (tab >= [tabView numberOfTabViewItems]) {
        NSBeep();
        return;
    }
    PTYTab *theTab = [[tabView tabViewItemAtIndex:tab] identifier];
    PTYSession *theSession = [theTab sessionWithViewId:view];
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

@end
