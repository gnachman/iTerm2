//
//  iTermStatusBarLayout+tmux.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/18.
//

#import "iTermStatusBarLayout+tmux.h"

#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarSwiftyStringComponent.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "TmuxController.h"

@interface iTermStatusBarTmuxLeftComponent : iTermStatusBarSwiftyStringComponent
@end

@implementation iTermStatusBarTmuxLeftComponent

- (NSArray<NSString *> *)stringVariants {
    NSArray *parts = [self.value ?: @"" componentsSeparatedByString:@" | "];
    NSMutableArray<NSString *> *variants = [NSMutableArray array];
    NSInteger count = parts.count;
    for (NSInteger i = count; i > 0; i--) {
        [variants addObject:[[parts subarrayToIndex:i] componentsJoinedByString:@" | "]];
    };
    return variants;
}

@end

@interface iTermStatusBarTmuxRightComponent : iTermStatusBarSwiftyStringComponent
@end

@implementation iTermStatusBarTmuxRightComponent

- (NSTextField *)newTextField {
    NSTextField *textField = [super newTextField];
    textField.alignment = NSTextAlignmentRight;
    return textField;
}

- (NSArray<NSString *> *)stringVariants {
    NSArray *parts = [self.value ?: @"" componentsSeparatedByString:@" | "];
    NSMutableArray<NSString *> *variants = [NSMutableArray array];
    NSInteger count = parts.count;
    for (NSInteger i = 0; i < count; i++) {
        [variants addObject:[[parts subarrayFromIndex:i] componentsJoinedByString:@" | "]];
    };
    return variants;
}

@end

@implementation iTermStatusBarLayout (tmux)

+ (NSDictionary *)tmux_configurationWithInterpolatedStringExpression:(NSString *)expression {
    NSString *interpolatedString = [NSString stringWithFormat:@"\\(%@)", expression];
    return @{ iTermStatusBarComponentConfigurationKeyKnobValues: @{ iTermStatusBarSwiftyStringComponentExpressionKey: interpolatedString } };
}

+ (instancetype)tmuxLayoutWithController:(TmuxController *)controller
                                   scope:(iTermVariableScope *)scope
                                  window:(int)window {
    NSDictionary<iTermStatusBarComponentConfigurationKey, id> *leftConfiguration;
    NSDictionary<iTermStatusBarComponentConfigurationKey, id> *rightConfiguration;

    leftConfiguration = [self tmux_configurationWithInterpolatedStringExpression:iTermVariableKeySessionTmuxStatusLeft];
    rightConfiguration = [self tmux_configurationWithInterpolatedStringExpression:iTermVariableKeySessionTmuxStatusRight];

    id<iTermStatusBarComponent> leftComponent = [[iTermStatusBarTmuxLeftComponent alloc] initWithConfiguration:leftConfiguration
                                                                                                         scope:scope];
    id<iTermStatusBarComponent> rightComponent = [[iTermStatusBarTmuxRightComponent alloc] initWithConfiguration:rightConfiguration
                                                                                                           scope:scope];
    id<iTermStatusBarComponent> springComponent = [[iTermStatusBarSpringComponent alloc] initWithConfiguration:@{}
                                                                                                         scope:scope];

    NSDictionary *layoutDict = [iTermProfilePreferences objectForKey:KEY_STATUS_BAR_LAYOUT
                                                           inProfile:[controller profileForWindow:window]];
    iTermStatusBarLayout *layout = [[iTermStatusBarLayout alloc] initWithDictionary:layoutDict
                                                                              scope:scope];
    layout.components = @[ leftComponent, springComponent, rightComponent ];
    return layout;
}

+ (BOOL)shouldOverrideLayout:(NSDictionary *)layout {
    NSArray *components = layout[iTermStatusBarLayoutKeyComponents];
    return ([components count] == 0);
}

@end
