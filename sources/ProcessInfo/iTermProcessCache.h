//
//  iTermProcessCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Foundation/Foundation.h>

#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProcessInfoProvider;
@class iTermProcessCollection;

// Posted on the main queue when the foreground-job ancestry chain of a tracked
// root PID changes (including becoming empty when the process is reaped). This
// is the event-driven signal that backs job-started / job-ended triggers, as
// opposed to inferring changes from the periodic title poll. userInfo:
//   iTermProcessCacheForegroundJobAncestorsPidKey: NSNumber (the tracked root pid)
//   iTermProcessCacheForegroundJobAncestorsKey: NSArray<NSString *> (deepest first, may be empty)
extern NSNotificationName const iTermProcessCacheForegroundJobAncestorsDidChangeNotification;
extern NSString *const iTermProcessCacheForegroundJobAncestorsPidKey;
extern NSString *const iTermProcessCacheForegroundJobAncestorsKey;

@interface iTermProcessCache : NSObject<ProcessInfoProvider>

+ (instancetype)sharedInstance;
+ (iTermProcessCollection *)newProcessCollection;

@end

NS_ASSUME_NONNULL_END
