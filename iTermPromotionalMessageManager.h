//
//  iTermPromotionalMessageManager.h
//  iTerm
//
//  Created by George Nachman on 5/7/15.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermPromotionalMessageManager : NSObject

+ (instancetype)sharedInstance;
- (void)scheduleDisplayIfNeeded;

@end
