//
//  iTermTmuxStatusBarMonitor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/18.
//

#import <Foundation/Foundation.h>

#import "NSTimer+iTerm.h"

@class TmuxGateway;
@class iTermVariableScope;

NS_ASSUME_NONNULL_BEGIN

@interface iTermTmuxStatusBarMonitor : NSObject

@property (nonatomic) BOOL active;
@property (nonatomic, weak) TmuxGateway *gateway;
@property (nonatomic, strong) iTermVariableScope *scope;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithGateway:(TmuxGateway *)gateway
                          scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
