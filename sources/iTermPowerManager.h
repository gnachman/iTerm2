//
//  iTermPowerManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/21/18.
//

#import <Foundation/Foundation.h>

// Posted when charging status changes
extern NSString *const iTermPowerManagerStateDidChange;

@interface iTermPowerManager : NSObject

@property (nonatomic, readonly) BOOL connectedToPower;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

@end
