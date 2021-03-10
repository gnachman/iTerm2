//
//  iTermAddTriggerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import "iTermAddTriggerViewController.h"

#import "iTermFocusablePanel.h"
#import "iTermHighlightLineTrigger.h"
#import "iTermUserDefaults.h"
#import "HighlightTrigger.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"
#import "Trigger.h"
#import "TriggerController.h"

#import <ColorPicker/ColorPicker.h>

@interface iTermAddTriggerViewController()<iTermTriggerParameterController>
@end

@implementation iTermAddTriggerViewController {
    IBOutlet NSTextField *_regexTextField;
    IBOutlet NSPopUpButton *_actionButton;
    IBOutlet NSView *_paramContainerView;
    IBOutlet NSButton *_instantButton;
    IBOutlet NSButton *_updateProfileButton;

    NSArray<Trigger *> *_triggers;
    NSView *_paramView;
    id _savedDelegate;

    NSString *_regex;
    BOOL _interpolatedStrings;
    void (^_completion)(NSDictionary *, BOOL);
    CGFloat _paramY;
    NSColor *_defaultTextColor;
    NSColor *_defaultBackgroundColor;
}

+ (void)addTriggerForText:(NSString *)text
                   window:(NSWindow *)window
      interpolatedStrings:(BOOL)interpolatedStrings
         defaultTextColor:(NSColor *)defaultTextColor
   defaultBackgroundColor:(NSColor *)defaultBackgroundColor
               completion:(void (^)(NSDictionary *, BOOL))completion {
    NSPanel *panel = [[iTermFocusablePanel alloc] initWithContentRect:NSZeroRect
                                                            styleMask:NSWindowStyleMaskTitled
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO
                                                               screen:nil];
    // List of characters to escape comes from ICU's documentation for the backslash meta-character.
    // Some characters like - only need to be escaped inside [sets] but it's safe to escape them
    // outside sets as well.
    NSString *charactersToEscape = @"\\*?+[(){}^$|.]-&";
    NSMutableString *regex = [text mutableCopy];
    for (NSInteger i = 0; i < charactersToEscape.length; i++) {
        NSString *c = [charactersToEscape substringWithRange:NSMakeRange(i, 1)];
        [regex replaceOccurrencesOfString:c
                               withString:[@"\\" stringByAppendingString:c]
                                  options:0
                                    range:NSMakeRange(0, regex.length)];
    }
    iTermAddTriggerViewController *vc = [[iTermAddTriggerViewController alloc] initWithName:text
                                                                                      regex:regex
                                                                        interpolatedStrings:interpolatedStrings
                                                                           defaultTextColor:defaultTextColor
                                                                     defaultBackgroundColor:defaultBackgroundColor
                                                                                 completion:
                                         ^(NSDictionary * _Nullable dict, BOOL updateProfile) {
        [window endSheet:panel returnCode:dict ? NSModalResponseOK : NSModalResponseCancel];
        completion(dict, updateProfile);
    }];
    [panel it_setAssociatedObject:vc forKey:"AddTriggerVC"];
    [panel setFrame:[NSPanel frameRectForContentRect:vc.view.bounds styleMask:panel.styleMask] display:NO];
    [panel.contentView addSubview:vc.view];
    panel.contentView.autoresizesSubviews = YES;
    vc.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vc.view.frame = panel.contentView.bounds;
    [window beginSheet:panel completionHandler:^(NSModalResponse returnCode) {}];
}


- (instancetype)initWithName:(NSString *)name
                       regex:(NSString *)regex
         interpolatedStrings:(BOOL)interpolatedStrings
            defaultTextColor:(NSColor *)defaultTextColor
      defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                  completion:(void (^)(NSDictionary * _Nullable, BOOL))completion {
    self = [super initWithNibName:NSStringFromClass([self class])
                           bundle:[NSBundle bundleForClass:[self class]]];
    if (self) {
        _regex = [regex copy];
        _interpolatedStrings = interpolatedStrings;
        _defaultTextColor = defaultTextColor;
        _defaultBackgroundColor = defaultBackgroundColor;
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    _paramY = NSMinY(_paramContainerView.frame);
    _regexTextField.stringValue = _regex;
    _instantButton.state = [iTermUserDefaults addTriggerInstant] ? NSControlStateValueOn : NSControlStateValueOff;
    _updateProfileButton.state = [iTermUserDefaults addTriggerUpdateProfile] ? NSControlStateValueOn : NSControlStateValueOff;
    _triggers = [[TriggerController triggerClasses] mapWithBlock:^id(Class triggerClass) {
        return [[triggerClass alloc] init];
    }];
    [_triggers enumerateObjectsUsingBlock:^(Trigger *_Nonnull trigger, NSUInteger idx, BOOL * _Nonnull stop) {
        [trigger reloadData];
        [_actionButton addItemWithTitle:[trigger.class title]];
    }];

    // Select highlight with colors based on text.
    for (Class theClass in @[ [iTermHighlightLineTrigger class], [HighlightTrigger class] ]) {
        Trigger<iTermColorSettable> *trigger = [self firstTriggerOfClass:theClass];
        if (trigger) {
            [trigger setTextColor:_defaultTextColor];
            [trigger setBackgroundColor:_defaultBackgroundColor];
            [_actionButton selectItemAtIndex:[_triggers indexOfObject:trigger]];
        } else {
            [_actionButton selectItemAtIndex:0];
        }
        [self updateCustomViewForTrigger:self.currentTrigger value:nil];
    }
}

- (__kindof Trigger *)firstTriggerOfClass:(Class)theClass {
    return [_triggers objectPassingTest:^BOOL(Trigger *element, NSUInteger index, BOOL *stop) {
        return [element isKindOfClass:theClass];
    }];
}

- (IBAction)selectionDidChange:(id)sender {
    [self updateCustomViewForTrigger:self.currentTrigger value:nil];
}

- (IBAction)ok:(id)sender {
    Trigger *trigger = [self currentTrigger];
    const BOOL instant = _instantButton.state == NSControlStateValueOn;
    const BOOL updateProfile = _updateProfileButton.state == NSControlStateValueOn;
    NSDictionary *triggerDictionary = @{ kTriggerActionKey: trigger.action,
                                         kTriggerRegexKey: _regexTextField.stringValue,
                                         kTriggerParameterKey: [[self currentTrigger] param] ?: @0,
                                         kTriggerPartialLineKey: @(instant),
                                         kTriggerDisabledKey: @NO };
    [iTermUserDefaults setAddTriggerInstant:instant];
    [iTermUserDefaults setAddTriggerUpdateProfile:updateProfile];
    _completion(triggerDictionary, updateProfile);
}

- (IBAction)cancel:(id)sender {
    _completion(nil, NO);
}

- (Trigger *)currentTrigger {
    const NSInteger index = [_actionButton indexOfSelectedItem];
    return _triggers[index];
}

- (void)updateCustomViewForTrigger:(Trigger *)trigger value:(id)value {
    id delegateToSave;
    NSView *view = [TriggerController viewForParameterForTrigger:self.currentTrigger
                                                            size:NSMakeSize(_paramContainerView.frame.size.width, 21)
                                                           value:value
                                                        receiver:self
                                             interpolatedStrings:_interpolatedStrings
                                                     delegateOut:&delegateToSave
                                                     wellFactory:^CPKColorWell *(NSRect frame, NSColor *color) {
        CPKColorWell *well = [[CPKColorWell alloc] initWithFrame:frame];
        well.noColorAllowed = YES;
        well.continuous = YES;
        well.color = color;
        well.target = self;
        well.action = @selector(colorWellDidChange:);
        return well;
    }];
    _savedDelegate = delegateToSave;

    NSPopUpButton *popup = [NSPopUpButton castFrom:view];
    if (popup) {
        popup.bordered = YES;
        popup.frame = _paramContainerView.bounds;
        NSRect frame = _paramContainerView.frame;
        frame.size.height = 25;
        frame.origin.y = _paramY - 4;
        _paramContainerView.frame = frame;
    } else {
        NSRect frame = _paramContainerView.frame;
        frame.size.height = 21;
        frame.origin.y = _paramY;
        _paramContainerView.frame = frame;
    }
    NSTextField *textField = [NSTextField castFrom:view];
    textField.bordered = YES;
    textField.drawsBackground = YES;

    [_paramView removeFromSuperview];
    _paramView = view;
    [_paramContainerView addSubview:view];
}

- (void)colorWellDidChange:(CPKColorWell *)colorWell {
    id<iTermColorSettable> trigger = (id)self.currentTrigger;
    if (![trigger conformsToProtocol:@protocol(iTermColorSettable)]) {
        return;
    }
    if ([colorWell.identifier isEqual:kTextColorWellIdentifier]) {
        [trigger setTextColor:colorWell.color];
    } else {
        [trigger setBackgroundColor:colorWell.color];
    }
}

#pragma mark - iTermTriggerParameterController

- (void)parameterPopUpButtonDidChange:(id)sender {
    [[self currentTrigger] setParam:[[self currentTrigger] objectAtIndex:[sender indexOfSelectedItem]]];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = [NSTextField castFrom:_paramView];
    [[self currentTrigger] setParam:textField.stringValue ?: @""];
}

@end
