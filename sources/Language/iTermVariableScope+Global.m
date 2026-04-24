//
//  iTermVariableScope+Global.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope+Global.h"

@implementation iTermVariableScope (Global)

+ (iTermVariableScope<iTermGlobalScope> *)globalsScope {
    iTermVariableScope<iTermGlobalScope> *scope = (iTermVariableScope<iTermGlobalScope> *)[[iTermVariableScope alloc] init];
    [scope addVariables:[iTermVariables globalInstance] toScopeNamed:nil];
    return (iTermVariableScope<iTermGlobalScope> *)scope;
}

- (NSNumber *)applicationPID {
    return [self valueForVariableName:iTermVariableKeyApplicationPID];
}

- (void)setApplicationPID:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyApplicationPID];
}

- (NSString *)localhostName {
    return [self valueForVariableName:iTermVariableKeyApplicationLocalhostName];
}

- (void)setLocalhostName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyApplicationLocalhostName];
}

- (NSString *)effectiveTheme {
    return [self valueForVariableName:iTermVariableKeyApplicationEffectiveTheme];
}

- (void)setEffectiveTheme:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeyApplicationEffectiveTheme];
}


@end
