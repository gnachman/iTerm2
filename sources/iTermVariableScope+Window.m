//
//  iTermVariableScope+Window.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope+Window.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Tab.h"
#import "NSDictionary+iTerm.h"

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

- (NSRect)frame {
    NSArray<NSNumber *> *array = [NSArray castFrom:[self valueForVariableName:iTermVariableKeyWindowFrame]];
    if (array.count != 4) {
        return NSZeroRect;
    }
    return NSMakeRect([array[0] doubleValue] ?: 0,
                      [array[1] doubleValue] ?: 0,
                      [array[2] doubleValue] ?: 0,
                      [array[3] doubleValue] ?: 0);
}

- (NSString *)style {
    return [self valueForVariableName:iTermVariableKeyWindowStyle];
}

@end
