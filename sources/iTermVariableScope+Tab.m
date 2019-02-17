//
//  iTermVariableScope+Tab.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope+Tab.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Window.h"


@implementation iTermVariableScope (Tab)

+ (instancetype)newTabScopeWithVariables:(iTermVariables *)variables {
    iTermVariableScope<iTermTabScope> *scope = [[self alloc] init];
    [scope addVariables:variables toScopeNamed:nil];
    return scope;
}

- (NSString *)tabTitleOverride {
    return [self valueForVariableName:iTermVariableKeyTabTitleOverride];
}

- (void)setTabTitleOverride:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyTabTitleOverride];
}

- (NSString *)tabTitleOverrideFormat {
    return [self valueForVariableName:iTermVariableKeyTabTitleOverrideFormat];
}

- (void)setTabTitleOverrideFormat:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyTabTitleOverrideFormat];
}

- (iTermVariableScope<iTermSessionScope> *)currentSession {
    return [iTermVariableScope newSessionScopeWithVariables:[self valueForVariableName:iTermVariableKeyTabCurrentSession]];
}

- (NSNumber *)tmuxWindow {
    return [self valueForVariableName:iTermVariableKeyTabTmuxWindow];
}

- (void)setTmuxWindow:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyTabTmuxWindow];
}

- (NSNumber *)tabID {
    return [self valueForVariableName:iTermVariableKeyTabID];
}

- (void)setTabID:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyTabID];
}

- (iTermVariableScope<iTermWindowScope> *)window {
    return [iTermVariableScope newWindowScopeWithVariables:[self valueForVariableName:iTermVariableKeyTabWindow]
                                              tabVariables:[[self variablesInScopeNamed:nil] lastObject]];
}

@end
