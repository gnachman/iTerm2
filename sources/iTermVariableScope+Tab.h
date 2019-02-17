//
//  iTermVariableScope+Tab.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermSessionScope;
@protocol iTermWindowScope;

@protocol iTermTabScope<NSObject>

@property (nullable, nonatomic, strong) NSString *tabTitleOverride;
@property (nullable, nonatomic, strong) NSString *tabTitleOverrideFormat;
@property (nullable, nonatomic, readonly) iTermVariableScope<iTermSessionScope> *currentSession;
@property (nullable, nonatomic, strong) NSNumber *tmuxWindow;
@property (nullable, nonatomic, strong) NSNumber *tabID;
@property (nullable, nonatomic, readonly) iTermVariableScope<iTermWindowScope> *window;

@end

@interface iTermVariableScope (Tab)<iTermTabScope>

+ (instancetype)newTabScopeWithVariables:(iTermVariables *)variables;

@end

NS_ASSUME_NONNULL_END
