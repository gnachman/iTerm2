//
//  iTermTmuxTitleMonitor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/2/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxGateway;
@class iTermVariableScope;

@interface iTermTmuxTitleMonitor : NSObject

@property (nonatomic, weak) TmuxGateway *gateway;
@property (nonatomic, strong) iTermVariableScope *scope;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithGateway:(TmuxGateway *)gateway
                          scope:(iTermVariableScope *)scope
                         format:(NSString *)format
                         target:(NSString *)tmuxTarget
                   variableName:(NSString *)variableName NS_DESIGNATED_INITIALIZER;

// Call this to stop the timer. The scope will no longer be updated.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
