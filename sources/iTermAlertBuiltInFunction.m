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
    [alert layout];
    [[alert window] makeFirstResponder:textField];

    NSWindow *window = [[[iTermController sharedInstance] terminalWithGuid:windowID] window];
    if (window) {
        [alert runSheetModalForWindow:window];
    } else {
        [alert runModal];
    }
    completion(textField.stringValue ?: @"", nil);
}

@end


@implementation iTermGetPolyModalAlertBuiltInFunction

+ (NSArray *) getCompletion:(NSMutableArray * ) items
                           :(NSModalResponse ) tag
                           :(NSString *) textFieldText
                           :(NSArray *) buttons
                           :(NSArray *) comboboxItems {
    NSMutableArray *checkboxArray ;
    if ([items[1] isEqual:@"checkbox"]) {
        checkboxArray = [[NSMutableArray alloc] initWithCapacity:1];
        [checkboxArray addObject:[NSNumber numberWithInt:-1]];
    } else {
        checkboxArray = [[NSMutableArray alloc] initWithCapacity:[items[1] count]];
        for (id cb in items[1]) {
            [checkboxArray addObject:[NSNumber numberWithInt:[cb state]]];
        }
    }
    NSString *buttonText = @"button";
    if ([buttons count] > 0) {
        buttonText = buttons[tag - 1000];
    }
    NSString *comboBoxText = @"";
    if ([comboboxItems count] > 0) {
        NSNumber *comboBoxIndex = [NSNumber numberWithInt:[items[0] indexOfSelectedItem]];
        if ([comboBoxIndex intValue] > -1) {
            comboBoxText = [comboboxItems objectAtIndex:[comboBoxIndex intValue]];
        }
    }
    return [NSArray arrayWithObjects:buttonText, textFieldText, comboBoxText, checkboxArray,  nil];
}
+ (NSRect)gegStackRectangle:(NSArray *)buttons
                           :(NSArray *)comboboxItems
                           :(NSArray *)checkboxes
                           :(NSArray *)textFieldArg
                           :(NSNumber *)alertWidth {
    float height = 0.0;
    if ([textFieldArg count] == 2) {
        height += 30.0;
    }
    if ([comboboxItems count] > 0) {
        height += 30.0;
    }
    height += [checkboxes count] * 25;
    return NSMakeRect(0, 0, alertWidth.integerValue, height);
}
+ (void)registerBuiltInFunction {
    static NSString *const title = @"title";
    static NSString *const subtitle = @"subtitle";
    static NSString *const buttons = @"buttons";
    static NSString *const checkboxes = @"checkboxes";
    static NSString *const checkboxDefaults = @"checkboxDefaults";
    static NSString *const comboboxItems = @"comboboxItems";
    static NSString *const comboboxDefault = @"comboboxDefault";
    static NSString *const textFieldArg = @"textFieldArg";
    static NSString *const alertWidth = @"width";
    static NSString *const window_id = @"window_id";

    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"get_poly_modal_alert"
                                     arguments:@{ title: [NSString class],
                                                  subtitle: [NSString class],
                                                  buttons: [NSArray class],
                                                  checkboxes: [NSArray class],
                                                  checkboxDefaults: [NSArray class],
                                                  comboboxItems: [NSArray class],
                                                  comboboxDefault: [NSString class],
                                                  textFieldArg: [NSArray class],
                                                  alertWidth: [NSNumber class],
                                                  window_id: [NSObject class] }
                             optionalArguments:[NSSet setWithObject:window_id]
                                 defaultValues:@{ window_id: @"" }
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self showPolyModalAlert:parameters[title]
                         subtitle:parameters[subtitle]
                          buttons:parameters[buttons]
                       checkboxes:parameters[checkboxes]
                checkboxDefaults:parameters[checkboxDefaults]
                   comboboxItems:parameters[comboboxItems]
                 comboboxDefault:parameters[comboboxDefault]
                       textFieldArg:parameters[textFieldArg]
                      alertWidth:parameters[alertWidth]
                         windowID:[NSString castFrom:parameters[window_id]]
                       completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func namespace:@"iterm2"];
}

+ (void)showPolyModalAlert:(NSString *)title
                  subtitle:(NSString *)subtitle
                   buttons:(NSArray *)buttons
                checkboxes:(NSArray *)checkboxes
         checkboxDefaults:(NSArray *)checkboxDefaults
            comboboxItems:(NSArray *)comboboxItems
          comboboxDefault:(NSString *)comboboxDefault
                textFieldArg:(NSArray *)textFieldArg
               alertWidth:(NSNumber *)alertWidth
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
    NSMutableArray *addedViews = [[NSMutableArray alloc] initWithCapacity:3];
    NSMutableArray *returnViews = [[NSMutableArray alloc] initWithCapacity:3];
    if ([comboboxItems count] > 0) {
        NSComboBox *comboBox = [[NSComboBox alloc] init];
        for (id combobox_item in comboboxItems) {
            NSString *comboboxElementText = [NSString castFrom:combobox_item];
            if (comboboxElementText) {
                [comboBox addItemWithObjectValue:comboboxElementText];
                if ([comboboxElementText isEqualToString:comboboxDefault]) {
                    [comboBox selectItemWithObjectValue:comboboxElementText];
                }
            }
        }
        [addedViews addObject:comboBox];
        [returnViews addObject:comboBox];
    } else {
        [returnViews addObject:@"comboBox"];
    }
    float vertOffset =  33;

    if ([checkboxes count] > 0) {
        NSMutableArray *checkboxViews = [[NSMutableArray alloc] initWithCapacity:[checkboxes count]];
        NSUInteger idx = 0;
        for (id checkbox in checkboxes) {
            NSButton *currentCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(59, vertOffset, 82, 32)];
            [currentCheckbox setButtonType:NSButtonTypeSwitch];
            [currentCheckbox setTitle:checkbox];
            NSUInteger st = [[checkboxDefaults objectAtIndex:idx] intValue];
            [currentCheckbox setState:st];
            [currentCheckbox setBezelStyle:NSBezelStylePush];
            [currentCheckbox setTarget:self];
            [checkboxViews addObject:currentCheckbox];
            [addedViews addObject:currentCheckbox];
            idx++;
        }
        [returnViews addObject:checkboxViews];
    } else {
        [returnViews addObject: @"checkbox"];
    };

    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    if ([textFieldArg count] == 2) {
        textField.editable = YES;
        textField.selectable = YES;
        textField.stringValue = textFieldArg[1];
        textField.placeholderString = textFieldArg[0];
        [addedViews addObject:textField];
        [returnViews addObject:textField];
    } else {
        [returnViews addObject:@"textFieldArg"];
    };
    NSStackView *stackView = [NSStackView stackViewWithViews:addedViews];
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeft;
    stackView.distribution = NSStackViewDistributionFill;
    stackView.clipsToBounds = true;
    stackView.frame = [self gegStackRectangle:buttons :comboboxItems :checkboxes :textFieldArg :alertWidth];
    stackView.translatesAutoresizingMaskIntoConstraints = true;
    alert.accessoryView = stackView;
    NSWindow *window = [[[iTermController sharedInstance] terminalWithGuid:windowID] window];
    NSModalResponse responseTag;
    if (window) {
        responseTag = [alert runSheetModalForWindow:window];
    } else {
        responseTag = [alert runModal];
    }
    completion([self getCompletion:returnViews :responseTag :textField.stringValue :buttons :comboboxItems], nil);
}
@end
