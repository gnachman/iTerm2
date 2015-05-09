// -*- mode:objc -*- vim: filetype=objcpp
// $Id: iTermGrowlDelegate.m,v 1.10 2006-10-09 22:24:52 yfabian Exp $
//
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
#import "PreferencePanel.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "iTermController.h"
#import "PseudoTerminal.h"
#import "Growl.framework/Headers/GrowlApplicationBridge.h"
#import "SessionView.h"

/**
 **  The category is used to extend iTermGrowlDelegate with private methods.
 **
 **  Any methods that should not be exposed to the 'outside world' by being
 **  included in the class header file should be declared here and implemented
 **  in @implementation.
 */
@interface
    iTermGrowlDelegate (PrivateMethods)
@end

@implementation iTermGrowlDelegate

+ (id)sharedInstance
{
    static iTermGrowlDelegate* shared = nil;
    if(!shared)
        shared = [iTermGrowlDelegate new];
    return shared;
}

- (id)init
{
    self = [super init];
    if (self) {
        notifications = [[NSArray arrayWithObjects:OURNOTIFICATIONS,
                          nil] retain];

        NSBundle *myBundle = [NSBundle bundleForClass:[iTermGrowlDelegate class]];
        NSString *growlPath = [[myBundle privateFrameworksPath] stringByAppendingPathComponent:@"Growl.framework"];
        NSBundle *growlBundle = [NSBundle bundleWithPath:growlPath];
        if (growlBundle && [growlBundle load]) {
            // Register ourselves as a Growl delegate
            [GrowlApplicationBridge setGrowlDelegate:self];
        } else {
            NSLog(@"Could not load Growl.framework");
        }

//        [GrowlApplicationBridge setGrowlDelegate:self];
        [self registrationDictionaryForGrowl];
        [self setEnabled:YES];

        return self;
    } else {
        return nil;
    }
}

- (void)dealloc
{
    [notifications release];
    [super dealloc];
}

- (BOOL)isEnabled
{
    return enabled;
}

- (void)setEnabled:(BOOL)newState
{
    enabled = newState;
}

- (void)growlNotify:(NSString *)title
{
    [self growlNotify:title withDescription:nil];
}

- (void)growlNotify:(NSString *)title
     withDescription:(NSString *)description
{
    [self growlNotify:title
      withDescription:description
      andNotification:DEFAULTNOTIFICATION];
}

- (void)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
{
      [self growlNotify:title
        withDescription:description
        andNotification:notification
             andSession:nil];
}

- (void)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
         andSession:(PTYSession *)session
{
    if (![self isEnabled]) {
        return;
    }

    NSDictionary *context = nil;
    if (session) {
        context = [[[NSDictionary alloc] initWithObjectsAndKeys:
                    [NSNumber numberWithInt:[[iTermController sharedInstance] indexOfTerminal:[[session tab] realParentWindow]]],
                    @"win",
                    [NSNumber numberWithInt:[[session tab] number]],
                    @"tab",
                    [NSNumber numberWithInt:[[session view] viewId]],
                    @"view",
                    nil] autorelease];
    }

    if ([[PreferencePanel sharedInstance] enableGrowl]) {
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:description
                               notificationName:notification
                                       iconData:nil
                                       priority:0
                                       isSticky:NO
                                   clickContext:context];
    }
}

- (void)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
         andURL:(NSString *)url {
    if (![self isEnabled]) {
        return;
    }

    NSDictionary *context = nil;
    if (url) {
        context = @{ @"url" : url };
    }

    if ([[PreferencePanel sharedInstance] enableGrowl]) {
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:description
                               notificationName:notification
                                       iconData:nil
                                       priority:0
                                       isSticky:NO
                                   clickContext:context];
    }
}

- (void)growlNotificationWasClicked:(id)clickContext {
    NSString *url = [clickContext objectForKey:@"url"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
        return;
    }
    
    int win = [[clickContext objectForKey:@"win"] intValue];
    int tab = [[clickContext objectForKey:@"tab"] intValue];
    int view = [[clickContext objectForKey:@"view"] intValue];

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

    if ([terminal isHotKeyWindow]) {
        [controller showHotKeyWindow];
    } else {
        [controller setCurrentTerminal:terminal];
        [[terminal window] makeKeyAndOrderFront:self];
        [tabView selectTabViewItemAtIndex:tab];
    }
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

    PTYTab *theTab = [terminal currentTab];
    PTYSession *theSession = [theTab sessionWithViewId:view];
    if (theSession) {
        [theTab setActiveSession:theSession];
    }
}

- (NSDictionary *)registrationDictionaryForGrowl
{
    NSDictionary *regDict = [NSDictionary dictionaryWithObjectsAndKeys:
        OURGROWLAPPNAME, GROWL_APP_NAME,
        notifications, GROWL_NOTIFICATIONS_ALL,
        notifications, GROWL_NOTIFICATIONS_DEFAULT,
        nil];

    return regDict;
}

- (void) growlIsReady
{
    NSLog(@"Growl is ready");
}

@end
