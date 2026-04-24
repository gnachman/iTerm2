//
//  iTermVariableScope+Global.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermGlobalScope<NSObject>

@property (nullable, nonatomic, strong) NSNumber *applicationPID;
@property (nullable, nonatomic, strong) NSString *localhostName;
@property (nullable, nonatomic, strong) NSString *effectiveTheme;

@end

@interface iTermVariableScope (Global)<iTermGlobalScope>
+ (iTermVariableScope<iTermGlobalScope> *)globalsScope;
@end

NS_ASSUME_NONNULL_END
