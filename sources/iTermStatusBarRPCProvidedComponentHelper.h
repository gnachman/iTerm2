//
//  iTermStatusBarRPCProvidedComponentHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/19.
//

#import <AppKit/AppKit.h>

#import "iTermAPIHelper.h"
#import "iTermObject.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermStatusBarRPCRegistrationRequestKey;

@interface iTermStatusBarRPCProvidedComponentHelper: NSObject<iTermObject>

// Nil if the last evaluation was successful.
@property (nullable, nonatomic, copy) NSString *errorMessage;
@property (nonatomic, readonly) NSString *invocation;

@end

@interface ITMRPCRegistrationRequest(StatusBar)
@property (nonatomic, readonly) NSDictionary *statusBarConfiguration;
- (instancetype)latestStatusBarRequest;
@end

NS_ASSUME_NONNULL_END
