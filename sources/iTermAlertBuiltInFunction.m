//
//  iTermAlertBuiltInFunction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/19.
//

#import "iTermAlertBuiltInFunction.h"
#import "NSObject+iTerm.h"

#import <Cocoa/Cocoa.h>

@implementation iTermAlertBuiltInFunction

+ (void)registerBuiltInFunction {
    static NSString *const title = @"title";
    static NSString *const subtitle = @"subtitle";
    static NSString *const buttons = @"buttons";

    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"alert"
                                     arguments:@{ title: [NSString class],
                                                  subtitle: [NSString class],
                                                  buttons: [NSArray class] }
                                 defaultValues:@{}
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self showAlertWithTitle:parameters[title]
                         subtitle:parameters[subtitle]
                          buttons:parameters[buttons]
                       completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)showAlertWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                   buttons:(NSArray *)buttons
                completion:(iTermBuiltInFunctionCompletionBlock)completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = subtitle;
    for (id button in buttons) {
        NSString *text = [NSString castFrom:button];
        if (text) {
            [alert addButtonWithTitle:text];
        }
    }
    completion(@(alert.runModal), nil);
}

@end
