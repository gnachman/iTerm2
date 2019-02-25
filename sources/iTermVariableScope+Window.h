//
//  iTermVariableScope+Window.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermTabScope;

@protocol iTermWindowScope<NSObject>

@property (nullable, nonatomic, strong) NSString *windowTitleOverrideFormat;
@property (nullable, nonatomic, readonly) NSString *windowTitleOverride;
@property (nullable, nonatomic, readonly) iTermVariableScope<iTermTabScope> *currentTab;

@end

@interface iTermVariableScope(Window)<iTermWindowScope>

+ (instancetype)newWindowScopeWithVariables:(iTermVariables *)variables
                               tabVariables:(iTermVariables *)tabVariables;
@end

NS_ASSUME_NONNULL_END
