//
//  iTermAlertBuiltInFunction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/19.
//

#import "iTermAlertBuiltInFunction.h"

#import "iTermController.h"
#import "NSAlert+iTerm.h"
#import "NSObject+iTerm.h"
#import "PTYSession.h"
#import "SessionView.h"

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

@implementation iTermGetStringBuiltInFunction

+ (void)registerBuiltInFunction {
    static NSString *const title = @"title";
    static NSString *const subtitle = @"subtitle";
    static NSString *const placeholder = @"placeholder";
    static NSString *const defaultValue = @"defaultValue";
    static NSString *const sessionID = @"sessionID";
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"get_string"
                                     arguments:@{ title: [NSString class],
                                                  subtitle: [NSString class],
                                                  placeholder: [NSString class],
                                                  defaultValue: [NSString class] }
                                 defaultValues:@{ sessionID: @"id" }
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self showAlertWithTextFieldAccessoryWithTitle:parameters[title]
                                               subtitle:parameters[subtitle]
                                            placeholder:parameters[placeholder]
                                           defaultValue:parameters[defaultValue]
                                              sessionID:parameters[sessionID]
                                             completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)showAlertWithTextFieldAccessoryWithTitle:(NSString *)title
                                        subtitle:(NSString *)subtitle
                                     placeholder:(NSString *)placeholder
                                    defaultValue:(NSString *)defaultValue
                                       sessionID:(NSString *)sessionID
                                      completion:(iTermBuiltInFunctionCompletionBlock)completion {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    textField.editable = YES;
    textField.selectable = YES;
    textField.stringValue = defaultValue;
    textField.placeholderString = placeholder;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = subtitle;
    alert.accessoryView = textField;

    PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:sessionID];
    NSWindow *window = session.view.window;
    if (window) {
        [alert runSheetModalForWindow:window];
    } else {
        [alert runModal];
    }
    completion(textField.stringValue ?: @"", nil);
}

@end

