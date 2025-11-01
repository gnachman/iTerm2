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
#import "NSArray+CommonAdditions.h"

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
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
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


@interface PolyModalItems : NSObject
@property (nonatomic, strong, nullable) NSArray<NSString *> *buttons;
@property (nonatomic, strong, nullable) NSArray<NSButton *> *checkboxes;
@property (nonatomic, strong, nullable) NSComboBox *comboBox;
@property (nonatomic, strong, nullable) NSTextField *textField;
@end

@implementation PolyModalItems
@end

@implementation iTermGetPolyModalAlertBuiltInFunction

+ (NSDictionary *)polyModalCompletion:(PolyModalItems *)polyModalItems
                                  tag:(NSModalResponse)tag {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    NSInteger index = tag - 1000;
    if (index >= 0 && index < [polyModalItems.buttons count]) {
        result[@"button"] = polyModalItems.buttons[index];
    }

    if (polyModalItems.textField) {
        result[@"tf_text"] = polyModalItems.textField.stringValue;
    }

    if (polyModalItems.checkboxes) {
        result[@"checks"] = [[polyModalItems.checkboxes
            mapToMutableArrayWithBlock:^id(NSButton *cb) {
                return (cb.state == NSControlStateValueOn) ? cb.title : nil;
            }] mutableCopy];
    }

    if (polyModalItems.comboBox) {
        NSInteger comboBoxIndex = [polyModalItems.comboBox indexOfSelectedItem];
        if (comboBoxIndex >= 0) {
            result[@"combo"] =
                [polyModalItems.comboBox itemObjectValueAtIndex:comboBoxIndex];
        } else {
            result[@"combo"] = @"";
        }
    }

    return result;
}
+ (NSRect)stackRectangle:(NSArray<NSString *> *)buttons
           comboboxItems:(NSArray<NSString *> *)comboboxItems
              checkboxes:(NSArray<NSString *> *)checkboxes
         textFieldParams:(NSArray<NSString *> *)textFieldParams
              alertWidth:(NSNumber *)alertWidth {
    
    CGFloat height = 0.0;
    if ([textFieldParams count] >= 2) {
        height += 30.0;
    }
    if ([comboboxItems count] > 0) {
        height += 30.0;
    }
    height += [checkboxes count] * 25;
    
    return NSMakeRect(0.0, 0.0, alertWidth.integerValue, height);
}
+ (void)registerBuiltInFunction {
    static NSString *const title = @"title";
    static NSString *const subtitle = @"subtitle";
    static NSString *const buttons = @"buttons";
    static NSString *const checkboxes = @"checkboxes";
    static NSString *const checkboxDefaults = @"checkboxDefaults";
    static NSString *const comboboxItems = @"comboboxItems";
    static NSString *const comboboxDefault = @"comboboxDefault";
    static NSString *const textFieldParams = @"textFieldParams";
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
                                                  textFieldParams: [NSArray class],
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
                 textFieldParams:parameters[textFieldParams]
                      alertWidth:parameters[alertWidth]
                         windowID:[NSString castFrom:parameters[window_id]]
                       completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func namespace:@"iterm2"];
}

+ (void)showPolyModalAlert:(NSString *)title
                  subtitle:(NSString *)subtitle
                   buttons:(NSArray<NSString *> *)buttons
                checkboxes:(NSArray<NSString *> *)checkboxes
          checkboxDefaults:(NSArray<NSNumber *> *)checkboxDefaults
             comboboxItems:(NSArray<NSString *> *)comboboxItems
           comboboxDefault:(NSString *)comboboxDefault
           textFieldParams:(NSArray<NSString *> *)textFieldParams
                alertWidth:(NSNumber *)alertWidth
                  windowID:(NSString *)windowID
                completion:(iTermBuiltInFunctionCompletionBlock)completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = subtitle;
    PolyModalItems *polyModalItems = [[PolyModalItems alloc] init];
    polyModalItems.buttons = buttons;
    for (id button in buttons) {
        NSString *buttonTitle = [NSString castFrom:button];
        if (buttonTitle) {
            [alert addButtonWithTitle:buttonTitle];
        }
    }
    NSMutableArray *stackViews = [NSMutableArray array];
    if ([comboboxItems count] > 0) {
        NSComboBox *comboBox = [[NSComboBox alloc] init];
        for (NSString *item in comboboxItems) {
            [comboBox addItemWithObjectValue:item];
            if ([item isEqualToString:comboboxDefault]) {
                [comboBox selectItemWithObjectValue:item];
            }
        }
        [stackViews addObject:comboBox];
        polyModalItems.comboBox = comboBox;
    }

    if ([checkboxes count] > 0) {
        NSMutableArray *checkboxViews = [NSMutableArray array];
        NSUInteger idx = 0;
        for (NSString *checkboxTitle in checkboxes) {
            NSButton *currentCheckbox =
                [[NSButton alloc] initWithFrame:NSZeroRect];
            currentCheckbox.translatesAutoresizingMaskIntoConstraints = YES;
            currentCheckbox.buttonType = NSButtonTypeSwitch;
            currentCheckbox.title = checkboxTitle;
            currentCheckbox.state = [[checkboxDefaults objectAtIndex:idx] integerValue];
            [checkboxViews addObject:currentCheckbox];
            [stackViews addObject:currentCheckbox];
            idx++;
        }
        polyModalItems.checkboxes = checkboxViews;
    }

    if ([textFieldParams count] >= 2) {
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        textField.editable = YES;
        textField.selectable = YES;
        textField.stringValue = textFieldParams[1];
        textField.placeholderString = textFieldParams[0];
        [stackViews addObject:textField];
        polyModalItems.textField = textField;
    }
    NSStackView *stackView = [NSStackView stackViewWithViews:stackViews];
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeft;
    stackView.distribution = NSStackViewDistributionFill;
    stackView.clipsToBounds = YES;
    stackView.frame = [self stackRectangle:buttons
                             comboboxItems:comboboxItems
                                checkboxes:checkboxes
                           textFieldParams:textFieldParams
                                alertWidth:alertWidth];
    stackView.translatesAutoresizingMaskIntoConstraints = YES;
    alert.accessoryView = stackView;
    [alert layout];
    if (polyModalItems.textField) {
        [[alert window] makeFirstResponder:polyModalItems.textField];
    }
    NSWindow *window =
        [[[iTermController sharedInstance] terminalWithGuid:windowID] window];
    NSModalResponse responseTag;
    if (window) {
        responseTag = [alert runSheetModalForWindow:window];
    } else {
        responseTag = [alert runModal];
    }
    completion([self polyModalCompletion:polyModalItems tag:responseTag], nil);
}
@end
