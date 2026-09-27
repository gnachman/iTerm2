//
//  iTermTabGroupBuiltInFunctions.m
//  iTerm2SharedARC
//

#import "iTermTabGroupBuiltInFunctions.h"

#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "iTermBuiltInFunctions.h"
#import "iTermController.h"
#import "iTermVariableHistory.h"

@implementation iTermTabGroupBuiltInFunctions

+ (void)registerBuiltInFunction {
    [self registerSetName];
    [self registerSetColor];
    [self registerSetCollapsed];
}

// The window that currently hosts the group. The same-window invariant means at
// most one window has members; returns nil when the group no longer exists
// (e.g. its last tab was closed).
+ (PseudoTerminal *)terminalForTabGroupID:(NSString *)groupID {
    if (groupID.length == 0) {
        return nil;
    }
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        if ([term tabsInGroup:groupID].count > 0) {
            return term;
        }
    }
    return nil;
}

+ (NSError *)noSuchGroupError {
    return [NSError errorWithDomain:@"com.iterm2.tab-group"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"TabGroup.NoSuchGroup", nil, [NSBundle mainBundle], @"No such tab group", @"Error when no tab group matches the given id") }];
}

+ (void)registerSetName {
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"set_tab_group_name"
                                     arguments:@{ @"group_id": [NSString class],
                                                  @"name": [NSString class] }
                             optionalArguments:[NSSet set]
                                 defaultValues:@{}
                                       context:iTermVariablesSuggestionContextApp
                        sideEffectsPlaceholder:@"[set_tab_group_name]"
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock _Nonnull completion) {
         NSString *groupID = parameters[@"group_id"];
         NSString *name = parameters[@"name"];
         PseudoTerminal *term = [self terminalForTabGroupID:groupID];
         if (!term) {
             completion(nil, [self noSuchGroupError]);
             return;
         }
         [term apiSetTabGroupNameWithCompletion:completion group_id:groupID name:name];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func namespace:@"iterm2"];
}

+ (void)registerSetColor {
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"set_tab_group_color"
                                     arguments:@{ @"group_id": [NSString class],
                                                  @"color": [NSString class] }
                             optionalArguments:[NSSet set]
                                 defaultValues:@{}
                                       context:iTermVariablesSuggestionContextApp
                        sideEffectsPlaceholder:@"[set_tab_group_color]"
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock _Nonnull completion) {
         NSString *groupID = parameters[@"group_id"];
         NSString *color = parameters[@"color"];
         PseudoTerminal *term = [self terminalForTabGroupID:groupID];
         if (!term) {
             completion(nil, [self noSuchGroupError]);
             return;
         }
         [term apiSetTabGroupColorWithCompletion:completion group_id:groupID color:color];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func namespace:@"iterm2"];
}

+ (void)registerSetCollapsed {
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"set_tab_group_collapsed"
                                     arguments:@{ @"group_id": [NSString class],
                                                  @"collapsed": [NSNumber class] }
                             optionalArguments:[NSSet set]
                                 defaultValues:@{}
                                       context:iTermVariablesSuggestionContextApp
                        sideEffectsPlaceholder:@"[set_tab_group_collapsed]"
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock _Nonnull completion) {
         NSString *groupID = parameters[@"group_id"];
         NSNumber *collapsed = parameters[@"collapsed"];
         PseudoTerminal *term = [self terminalForTabGroupID:groupID];
         if (!term) {
             completion(nil, [self noSuchGroupError]);
             return;
         }
         [term apiSetTabGroupCollapsedWithCompletion:completion group_id:groupID collapsed:collapsed];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func namespace:@"iterm2"];
}

@end
