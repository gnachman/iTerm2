//
//  iTermVariableScope+Window.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope+Window.h"
#import "iTermVariableScope+Global.h"

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

- (iTermVariableScope<iTermTabScope> *)currentTab {
    return [self valueForVariableName:iTermVariableKeyWindowCurrentTab];
}

- (void)setCurrentTab:(iTermVariableScope<iTermTabScope> *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyWindowCurrentTab];
}


@end
