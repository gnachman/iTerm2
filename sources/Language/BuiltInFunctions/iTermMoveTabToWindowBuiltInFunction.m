//
//  iTermMoveTabToWindowBuiltInFunction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/19.
//

#import "iTermMoveTabToWindowBuiltInFunction.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "iTermController.h"
#import "iTermVariables.h"

@implementation iTermMoveTabToWindowBuiltInFunction

+ (void)registerBuiltInFunction {
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"move_tab_to_window"
                                     arguments:@{ }
                             optionalArguments:[NSSet set]
                                 defaultValues:@{ @"tab_id": iTermVariableKeyTabID }
                                       context:iTermVariablesSuggestionContextTab
                        sideEffectsPlaceholder:@"[move_tab_to_window]"
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         NSString *tabID = parameters[@"tab_id"];
         [self moveTabWithID:tabID completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)moveTabWithID:(NSString *)tabID completion:(iTermBuiltInFunctionCompletionBlock)completion {
    PTYTab *tab = [[iTermController sharedInstance] tabWithID:tabID];
    if (!tabID) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:1
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"MoveTabToWindow.NoSuchTab", nil, [NSBundle mainBundle], @"No such tab", @"Error when no tab matches the given tab_id") }]);
        return;
    }

    PseudoTerminal *term = [[iTermController sharedInstance] terminalWithTab:tab];
    if (!term) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:2
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"MoveTabToWindow.TabHasNoWindow", nil, [NSBundle mainBundle], @"Tab has no window", @"Error when the tab is not in any window") }]);
        return;
    }

    if (term.tabs.count < 2) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:3
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"MoveTabToWindow.WindowHasOnlyOneTab", nil, [NSBundle mainBundle], @"Window has only one tab", @"Error when the window has only one tab so it cannot be moved out") }]);
        return;
    }
    PseudoTerminal *newWindowController = [term it_moveTabToNewWindow:tab];
    if (!newWindowController) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:4
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"MoveTabToWindow.FailedToCreateWindow", nil, [NSBundle mainBundle], @"Failed to create new window", @"Error when creating a new window for the tab fails") }]);
        return;
    }

    completion(newWindowController.terminalGuid, nil);
}

@end
