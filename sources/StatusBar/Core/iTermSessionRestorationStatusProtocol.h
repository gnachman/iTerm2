//
//  iTermSessionRestorationStatusProtocol.h
//  iTerm2
//
//  Created by Claude on 6/24/25.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Notification posted when session restoration completes
extern NSString *const iTermSessionRestorationDidCompleteNotification;

/**
 * Protocol for objects that can indicate whether they are currently performing session restoration.
 * This is used to defer expensive operations (like WKWebView URL loading) during restoration.
 */
@protocol iTermSessionRestorationStatusProtocol <NSObject>

/**
 * @return YES if session restoration is currently in progress, NO otherwise.
 */
@property (nonatomic, readonly) BOOL isPerformingSessionRestoration;

@end

NS_ASSUME_NONNULL_END
