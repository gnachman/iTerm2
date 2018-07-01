//
//  iTermStatusBarBaseComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import <Foundation/Foundation.h>
#import "iTermStatusBarComponent.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

@interface iTermStatusBarBaseComponent : NSObject<iTermStatusBarComponent>

@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSDictionary<iTermStatusBarComponentConfigurationKey, id> *configuration;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
