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
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import <UserNotifications/UserNotifications.h>

@interface iTermNotificationController ()<UNUserNotificationCenterDelegate>
- (void)notificationWasClicked:(NSDictionary *)clickContext;
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
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;

        // Request notification authorization
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (error) {
                DLog(@"Notification authorization error: %@", error);
            }
        }];
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
         withImage:(NSString *)imagePath
       windowIndex:(int)windowIndex
          tabIndex:(int)tabIndex
         viewIndex:(int)viewIndex {
    DLog(@"NotifyRich title=%@ description=%@ window=%@ tab=%@ view=%@",
         title, description, @(windowIndex), @(tabIndex), @(viewIndex));

    if (description == nil) {
        DLog(@"notifyRich passed nil description.");
        return NO;
    }

    NSDictionary *context = nil;
    if (windowIndex >= 0) {
        context = @{ @"win": @(windowIndex),
                     @"tab": @(tabIndex),
                     @"view": @(viewIndex) };
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"";
    content.subtitle = subtitle ?: @"";
    content.body = description;
    content.userInfo = context ?: @{};
    content.sound = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : [UNNotificationSound defaultSound];

    // Add an image to the notification if available
    if (imagePath) {
        NSURL *imageURL = [NSURL fileURLWithPath:imagePath];
        NSError *error = nil;
        UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"image"
                                                                                              URL:imageURL
                                                                                          options:nil
                                                                                            error:&error];
        if (!error) {
            content.attachments = @[attachment];
        } else {
            DLog(@"Failed to add image to notification: %@", error);
        }
    }

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    NSString *identifier = [NSUUID UUID].UUIDString;
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:trigger];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"Error posting notification: %@", error);
        }
    }];

    return YES;
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

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"";
    content.body = description ?: @"";
    content.sound = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : [UNNotificationSound defaultSound];
    content.userInfo = context ?: @{};
    DLog(@"Post notification %@", content);

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    NSString *identifier = [NSUUID UUID].UUIDString;
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:trigger];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"Error posting notification: %@", error);
        }
    }];

    return YES;
}

- (void)postNotificationWithTitle:(NSString *)title detail:(NSString *)detail URL:(NSURL *)url {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = detail;
    content.sound = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : [UNNotificationSound defaultSound];
    if (url) {
        content.userInfo = @{ @"URL": url.absoluteString };
    }

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    NSString *identifier = [NSUUID UUID].UUIDString;

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:trigger];

    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"Error posting notification: %@", error);
        }
    }];
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
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = detail;
    content.sound = [iTermAdvancedSettingsModel silentUserNotifications] ? nil : [UNNotificationSound defaultSound];
    content.userInfo = @{ @"CallbackNotificationName": name,
                          @"CallbackUserInfo": userInfo ?: @{} };

    if (actionButtonTitle) {
        content.categoryIdentifier = @"actionCategory";
        UNNotificationAction *action = [UNNotificationAction actionWithIdentifier:@"actionButton"
                                                                             title:actionButtonTitle
                                                                           options:UNNotificationActionOptionForeground];
        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"actionCategory"
                                                                                  actions:@[action]
                                                                        intentIdentifiers:@[]
                                                                                  options:UNNotificationCategoryOptionNone];
        [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:[NSSet setWithObject:category]];
    }

    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    NSString *identifier = [NSUUID UUID].UUIDString;

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:trigger];

    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"Error posting notification: %@", error);
        }
    }];
}

- (void)notificationWasClicked:(NSDictionary *)clickContext {
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

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    [self notificationWasClicked:response.notification.request.content.userInfo];
    completionHandler();
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
}

@end

