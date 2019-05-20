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
#import "PseudoTerminal.h"
#import "SessionView.h"

#import <Cocoa/Cocoa.h>

@implementation iTermAlertBuiltInFunction

+ (void)registerBuiltInFunction {
    static NSString *const title = @"title";
    static NSString *const subtitle = @"subtitle";
    static NSString *const buttons = @"buttons";
    static NSString *const window_id = @"window_id";

    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"alert"
                                     arguments:@{ title: [NSString class],
                                                  subtitle: [NSString class],
                                                  buttons: [NSArray class],
                                                  window_id: [NSObject class] }
                             optionalArguments:[NSSet setWithObject:window_id]
                                 defaultValues:@{ window_id: @"" }
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self showAlertWithTitle:parameters[title]
                         subtitle:parameters[subtitle]
                          buttons:parameters[buttons]
                         windowID:[NSString castFrom:parameters[window_id]]
                       completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)showAlertWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                   buttons:(NSArray *)buttons
                  windowID:(NSString *)windowID
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
    NSWindow *window = [[[iTermController sharedInstance] terminalWithGuid:windowID] window];
    if (window) {
        completion(@([alert runSheetModalForWindow:window]), nil);
    } else {
        completion(@(alert.runModal), nil);
    }
}

@end

@implementation iTermGetStringBuiltInFunction

+ (void)registerBuiltInFunction {
    static NSString *const title = @"title";
    static NSString *const subtitle = @"subtitle";
    static NSString *const placeholder = @"placeholder";
    static NSString *const defaultValue = @"defaultValue";
    static NSString *const window_id = @"window_id";
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"get_string"
                                     arguments:@{ title: [NSString class],
                                                  subtitle: [NSString class],
                                                  placeholder: [NSString class],
                                                  defaultValue: [NSString class],
                                                  window_id: [NSObject class] }
                             optionalArguments:[NSSet setWithObject:window_id]
                                 defaultValues:@{ }
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self showAlertWithTextFieldAccessoryWithTitle:parameters[title]
                                               subtitle:parameters[subtitle]
                                            placeholder:parameters[placeholder]
                                           defaultValue:parameters[defaultValue]
                                               windowID:[NSString castFrom:parameters[window_id]]
                                             completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)showAlertWithTextFieldAccessoryWithTitle:(NSString *)title
                                        subtitle:(NSString *)subtitle
                                     placeholder:(NSString *)placeholder
                                    defaultValue:(NSString *)defaultValue
                                        windowID:(NSString *)windowID
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

    NSWindow *window = [[[iTermController sharedInstance] terminalWithGuid:windowID] window];
    if (window) {
        [alert runSheetModalForWindow:window];
    } else {
        [alert runModal];
    }
    completion(textField.stringValue ?: @"", nil);
}

@end

