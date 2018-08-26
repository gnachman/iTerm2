//
//  iTermStatusBarLayout+tmux.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/18.
//

#import "iTermStatusBarLayout+tmux.h"

#import "iTermStatusBarComponent.h"
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarSwiftyStringComponent.h"
#import "iTermVariables.h"

@implementation iTermStatusBarLayout (tmux)

+ (NSDictionary *)tmux_configurationWithInterpolatedStringExpression:(NSString *)expression {
    NSString *interpolatedString = [NSString stringWithFormat:@"\\(%@)", expression];
    return @{ iTermStatusBarComponentConfigurationKeyKnobValues: @{ iTermStatusBarSwiftyStringComponentExpressionKey: interpolatedString } };
}

+ (instancetype)tmuxLayout {
    NSDictionary<iTermStatusBarComponentConfigurationKey, id> *leftConfiguration;
    NSDictionary<iTermStatusBarComponentConfigurationKey, id> *rightConfiguration;

    leftConfiguration = [self tmux_configurationWithInterpolatedStringExpression:iTermVariableKeySessionTmuxStatusLeft];
    rightConfiguration = [self tmux_configurationWithInterpolatedStringExpression:iTermVariableKeySessionTmuxStatusRight];

    id<iTermStatusBarComponent> leftComponent = [[iTermStatusBarSwiftyStringComponent alloc] initWithConfiguration:leftConfiguration];
    id<iTermStatusBarComponent> rightComponent = [[iTermStatusBarSwiftyStringComponent alloc] initWithConfiguration:rightConfiguration];
    id<iTermStatusBarComponent> springComponent = [[iTermStatusBarSpringComponent alloc] initWithConfiguration:@{}];

    return [[self alloc] initWithComponents:@[ leftComponent, springComponent, rightComponent ]];
}

+ (BOOL)shouldOverrideLayout:(NSDictionary *)layout {
    NSArray *components = layout[iTermStatusBarLayoutKeyComponents];
    return ([components count] == 0);
}

@end
