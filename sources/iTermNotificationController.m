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
#import "NSImage+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

@interface iTermNotificationController ()
- (void)notificationWasClicked:(id)clickContext;
- (void)ensureNotificationPermissionsWithCompletion:(void (^)(BOOL granted))completion;
@property (nonatomic, strong) NSMutableArray<void (^)(BOOL granted)> *pendingPermissionCompletions;
@property (nonatomic, assign) BOOL checkingPermissions;
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
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;
        _pendingPermissionCompletions = [NSMutableArray array];
        _checkingPermissions = NO;
    }
    return self;
}

- (void)ensureNotificationPermissionsWithCompletion:(void (^)(BOOL granted))completion {
    [self.pendingPermissionCompletions addObject:completion];
    
    if (self.checkingPermissions) {
        return;
    }
    
    self.checkingPermissions = YES;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        DLog(@"auth status %@", @(settings.authorizationStatus));
        switch (settings.authorizationStatus) {
            case UNAuthorizationStatusAuthorized:
                [self invokeAllPendingCompletionsWithResult:YES];
                break;
                
            case UNAuthorizationStatusNotDetermined: {
                [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                      completionHandler:^(BOOL authGranted, NSError * _Nullable error) {
                    if (error) {
                        DLog(@"Notification authorization error: %@", error);
                    }
                    DLog(@"granted=%@", @(authGranted));
                    [self invokeAllPendingCompletionsWithResult:authGranted];
                }];
                break;
            }

            case UNAuthorizationStatusDenied:
            case UNAuthorizationStatusProvisional:
            default:
                [self invokeAllPendingCompletionsWithResult:NO];
                break;
        }
    }];
}

- (void)invokeAllPendingCompletionsWithResult:(BOOL)granted {
    NSArray<void (^)(BOOL granted)> *completions = [self.pendingPermissionCompletions copy];
    [self.pendingPermissionCompletions removeAllObjects];
    self.checkingPermissions = NO;
    
    for (void (^completion)(BOOL granted) in completions) {
        completion(granted);
    }
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

    [self ensureNotificationPermissionsWithCompletion:^(BOOL granted) {
        if (!granted) {
            DLog(@"Notification permission not granted");
            return;
        }
        
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.body = description;
        
        NSDictionary *context = nil;
        if (windowIndex >= 0) {
            context = @{ @"win": @(windowIndex),
                         @"tab": @(tabIndex),
                         @"view": @(viewIndex) };
        }
        content.userInfo = context ?: @{};
        
        if (title != nil) {
            content.title = title;
        }
        if (subtitle != nil) {
            content.subtitle = subtitle;
        }
        if (image != nil) {
            NSData *data = [NSData dataWithContentsOfFile:image];
            if (data != nil) {
                NSImage *nsImage = [[[iTermImage imageWithCompressedData:data] images] firstObject];
                if (nsImage) {
                    NSString *tempDir = NSTemporaryDirectory();
                    NSString *filename = [NSString stringWithFormat:@"iterm-notification-image-%f.png", [NSDate timeIntervalSinceReferenceDate]];
                    NSString *tempPath = [tempDir stringByAppendingPathComponent:filename];
                    
                    [nsImage saveAsPNGTo:tempPath];
                    
                    NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
                    NSError *error = nil;
                    UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"image"
                                                                                                             URL:tempURL
                                                                                                         options:nil
                                                                                                           error:&error];
                    if (attachment && !error) {
                        content.attachments = @[attachment];
                    } else if (error) {
                        DLog(@"Error creating notification attachment: %@", error);
                    }
                }
            }
        }
        
        if (![iTermAdvancedSettingsModel silentUserNotifications]) {
            content.sound = [UNNotificationSound defaultSound];
        }
        
        NSString *identifier = [NSString stringWithFormat:@"iterm-notification-%f", [NSDate timeIntervalSinceReferenceDate]];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                              content:content
                                                                              trigger:nil];
        
        DLog(@"Post notification %@", request);
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                               withCompletionHandler:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"Error posting notification: %@", error);
            }
        }];
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
    
    [self ensureNotificationPermissionsWithCompletion:^(BOOL granted) {
        if (!granted) {
            DLog(@"Notification permission not granted");
            return;
        }
        
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title ?: @"";
        content.body = description ?: @"";
        
        NSDictionary *context = nil;
        if (windowIndex >= 0) {
            context = @{ @"win": @(windowIndex),
                         @"tab": @(tabIndex),
                         @"view": @(viewIndex) };
        }
        content.userInfo = context ?: @{};
        
        if (![iTermAdvancedSettingsModel silentUserNotifications]) {
            content.sound = [UNNotificationSound defaultSound];
        }
        
        NSString *identifier = [NSString stringWithFormat:@"iterm-notification-%f", [NSDate timeIntervalSinceReferenceDate]];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                              content:content
                                                                              trigger:nil];
        
        DLog(@"Post notification %@", request);
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                               withCompletionHandler:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"Error posting notification: %@", error);
            }
        }];
    }];

    return YES;
}

- (void)postNotificationWithTitle:(NSString *)title detail:(NSString *)detail URL:(NSURL *)url {
    [self ensureNotificationPermissionsWithCompletion:^(BOOL granted) {
        if (!granted) {
            DLog(@"Notification permission not granted");
            return;
        }
        
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title ?: @"";
        content.body = detail ?: @"";
        content.userInfo = @{ @"URL": url.absoluteString ?: @"" };
        
        if (![iTermAdvancedSettingsModel silentUserNotifications]) {
            content.sound = [UNNotificationSound defaultSound];
        }
        
        NSString *identifier = [NSString stringWithFormat:@"iterm-notification-%f", [NSDate timeIntervalSinceReferenceDate]];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                              content:content
                                                                              trigger:nil];
        
        DLog(@"Post notification %@", request);
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                               withCompletionHandler:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"Error posting notification: %@", error);
            }
        }];
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
    [self ensureNotificationPermissionsWithCompletion:^(BOOL granted) {
        if (!granted) {
            DLog(@"Notification permission not granted");
            return;
        }
        
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title ?: @"";
        content.body = detail ?: @"";
        content.userInfo = @{ @"CallbackNotificationName": name ?: @"",
                              @"CallbackUserInfo": userInfo ?: @{} };
        
        if (![iTermAdvancedSettingsModel silentUserNotifications]) {
            content.sound = [UNNotificationSound defaultSound];
        }
        
        if (actionButtonTitle) {
            UNNotificationAction *action = [UNNotificationAction actionWithIdentifier:@"action"
                                                                                title:actionButtonTitle
                                                                              options:UNNotificationActionOptionForeground];
            UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"actionable"
                                                                                       actions:@[action]
                                                                             intentIdentifiers:@[]
                                                                                       options:UNNotificationCategoryOptionNone];
            [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:[NSSet setWithObject:category]];
            content.categoryIdentifier = @"actionable";
        }
        
        NSString *identifier = [NSString stringWithFormat:@"iterm-notification-%f", [NSDate timeIntervalSinceReferenceDate]];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                              content:content
                                                                              trigger:nil];
        
        DLog(@"Post notification %@", request);
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                               withCompletionHandler:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"Error posting notification: %@", error);
            }
        }];
    }];
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
        [[NSWorkspace sharedWorkspace] it_openURL:url];
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

#pragma mark UNUserNotificationCenterDelegate Methods

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    [self notificationWasClicked:response.notification.request.content.userInfo];
    completionHandler();
}

@end
