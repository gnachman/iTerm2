//
//  iTermVariableScope+Window.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope+Window.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Tab.h"

@implementation iTermVariableScope (Window)

+ (instancetype)newWindowScopeWithVariables:(iTermVariables *)variables
                               tabVariables:(iTermVariables *)tabVariables {
    iTermVariableScope<iTermWindowScope> *scope = [[self alloc] init];
    [scope addVariables:variables toScopeNamed:nil];
    [scope addVariables:[iTermVariables globalInstance] toScopeNamed:iTermVariableKeyGlobalScopeName];
    [scope setValue:tabVariables forVariableNamed:iTermVariableKeyWindowCurrentTab];
    return scope;
}

- (NSString *)windowTitleOverrideFormat {
    return [self valueForVariableName:iTermVariableKeyWindowTitleOverrideFormat];
}

- (void)setWindowTitleOverrideFormat:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyWindowTitleOverrideFormat];
}

- (NSString *)windowTitleOverride {
    return [self valueForVariableName:iTermVariableKeyWindowTitleOverride];
}

- (iTermVariableScope<iTermTabScope> *)currentTab {
    return [iTermVariableScope newTabScopeWithVariables:[self valueForVariableName:iTermVariableKeyWindowCurrentTab]];
}

- (NSString *)windowID {
    return [self valueForVariableName:iTermVariableKeyWindowID];
}

- (void)setWindowID:(NSString *)identifier {
    [self setValue:identifier forVariableNamed:iTermVariableKeyWindowID];
}

@end
