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
                                 defaultValues:@{ @"tab_id": iTermVariableKeyTabID }
                                       context:iTermVariablesSuggestionContextTab
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
                                        userInfo:@{ NSLocalizedDescriptionKey: @"No such tab" }]);
        return;
    }

    PseudoTerminal *term = [[iTermController sharedInstance] terminalWithTab:tab];
    if (!term) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:2
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Tab has no window" }]);
        return;
    }

    if (term.tabs.count < 2) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:3
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Window has only one tab" }]);
    }
    PseudoTerminal *newWindowController = [term moveTabToNewWindow:tab];
    if (!newWindowController) {
        completion(nil, [NSError errorWithDomain:@"com.iterm2.move-tab-to-window"
                                            code:4
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Failed to create new window" }]);
        return;
    }

    completion(newWindowController.terminalGuid, nil);
}

@end
