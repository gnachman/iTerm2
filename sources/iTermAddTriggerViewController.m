//
//  iTermAddTriggerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import "iTermAddTriggerViewController.h"

#import "ITAddressBookMgr.h"
#import "iTermFocusablePanel.h"
#import "iTermHighlightLineTrigger.h"
#import "iTermOptionallyBordered.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermTuple.h"
#import "iTermUserDefaults.h"
#import "HighlightTrigger.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"
#import "Trigger.h"
#import "TriggerController.h"

#import <ColorPicker/ColorPicker.h>

static const CGFloat kLabelWidth = 124;

@interface iTermAddTriggerViewController()<iTermTriggerParameterController>
@end

@implementation iTermAddTriggerViewController {
    NSTextField *_regexTextField;
    NSTextField *_nameTextField;
    NSPopUpButton *_actionButton;
    NSView *_paramContainerView;
    NSButton *_instantButton;
    NSButton *_updateProfileButton;
    NSButton *_okButton;
    NSButton *_cancelButton;
    NSButton *_enabledButton;
    NSButton *_toggleVisualizationButton;
    NSPopUpButton *_matchTypeButton;
    
    NSArray<Trigger *> *_triggers;
    NSView *_paramView;
    id _savedDelegate;

    BOOL _interpolatedStrings;
    BOOL _browserMode;
    iTermTriggerMatchType _matchType;
    void (^_completion)(NSDictionary *, BOOL);
    CGFloat _paramY;
    NSColor *_defaultTextColor;
    NSColor *_defaultBackgroundColor;
    iTermRegexVisualizationViewController *_visualizationViewController;
    NSPopover *_popover;
}

+ (void)addTriggerForText:(NSString *)text
                   window:(NSWindow *)window
      interpolatedStrings:(BOOL)interpolatedStrings
         defaultTextColor:(NSColor *)defaultTextColor
   defaultBackgroundColor:(NSColor *)defaultBackgroundColor
               completion:(void (^)(NSDictionary *, BOOL))completion {
    [self addTriggerForText:text
                     window:window
        interpolatedStrings:interpolatedStrings
           defaultTextColor:defaultTextColor
     defaultBackgroundColor:defaultBackgroundColor
                browserMode:NO
                 completion:completion];
}

+ (void)addTriggerForText:(NSString *)text
                   window:(NSWindow *)window
      interpolatedStrings:(BOOL)interpolatedStrings
         defaultTextColor:(NSColor *)defaultTextColor
   defaultBackgroundColor:(NSColor *)defaultBackgroundColor
              browserMode:(BOOL)browserMode
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
                                                                                browserMode:browserMode
                                                                                 completion:
                                         ^(NSDictionary * _Nullable dict, BOOL updateProfile) {
        [window endSheet:panel returnCode:dict ? NSModalResponseOK : NSModalResponseCancel];
        completion(dict, updateProfile);
    }];
    [panel it_setAssociatedObject:vc forKey:"AddTriggerVC"];
    
    // Force view loading to establish proper size
    if (@available(macOS 14.0, *)) {
        [vc loadViewIfNeeded];
    } else {
        // For macOS 12 compatibility
        [vc view];
    }
    
    // Set an explicit size for the content since we're using programmatic views
    CGFloat height = browserMode ? 241 : 208;  // Extra 33 points for match type row
    NSSize contentSize = NSMakeSize(480, height);
    NSRect contentRect = NSMakeRect(0, 0, contentSize.width, contentSize.height);
    
    [panel setFrame:[NSPanel frameRectForContentRect:contentRect styleMask:panel.styleMask] display:NO];
    [panel.contentView addSubview:vc.view];
    
    // Set up constraints to fill the panel content view
    vc.view.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view
                                                                  attribute:NSLayoutAttributeTop
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:panel.contentView
                                                                  attribute:NSLayoutAttributeTop
                                                                 multiplier:1.0
                                                                   constant:0]];
    [panel.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view
                                                                  attribute:NSLayoutAttributeLeading
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:panel.contentView
                                                                  attribute:NSLayoutAttributeLeading
                                                                 multiplier:1.0
                                                                   constant:0]];
    [panel.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view
                                                                  attribute:NSLayoutAttributeTrailing
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:panel.contentView
                                                                  attribute:NSLayoutAttributeTrailing
                                                                 multiplier:1.0
                                                                   constant:0]];
    [panel.contentView addConstraint:[NSLayoutConstraint constraintWithItem:vc.view
                                                                  attribute:NSLayoutAttributeBottom
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:panel.contentView
                                                                  attribute:NSLayoutAttributeBottom
                                                                 multiplier:1.0
                                                                   constant:0]];
    
    [window beginSheet:panel completionHandler:^(NSModalResponse returnCode) {}];
}


- (instancetype)initWithName:(NSString *)name
                       regex:(NSString *)regex
         interpolatedStrings:(BOOL)interpolatedStrings
            defaultTextColor:(NSColor *)defaultTextColor
      defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                 browserMode:(BOOL)browserMode
                  completion:(void (^)(NSDictionary * _Nullable, BOOL))completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _regex = [regex copy];
        _interpolatedStrings = interpolatedStrings;
        _defaultTextColor = defaultTextColor;
        _defaultBackgroundColor = defaultBackgroundColor;
        _completion = [completion copy];
        _browserMode = browserMode;
        _matchType = browserMode ? iTermTriggerMatchTypeURLRegex : iTermTriggerMatchTypeRegex;
    }
    return self;
}

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _regex = @"";
        _interpolatedStrings = NO;
        _defaultTextColor = [NSColor colorWithDisplayP3Red:1 green:1 blue:1 alpha:0];
        _defaultBackgroundColor = [NSColor colorWithDisplayP3Red:1 green:0 blue:0 alpha:1];
        _completion = ^(NSDictionary *ignore, BOOL ignore2) {};
        _browserMode = NO;
        _matchType = iTermTriggerMatchTypeRegex;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _regex = @"";
        _interpolatedStrings = NO;
        _defaultTextColor = [NSColor colorWithDisplayP3Red:1 green:1 blue:1 alpha:0];
        _defaultBackgroundColor = [NSColor colorWithDisplayP3Red:1 green:0 blue:0 alpha:1];
        _completion = ^(NSDictionary *ignore, BOOL ignore2) {};
        _browserMode = NO;
        _matchType = iTermTriggerMatchTypeRegex;
    }
    return self;
}

- (void)setTrigger:(Trigger *)trigger {
    _regex = [trigger.regex copy];
    _regexTextField.stringValue = _regex;
    _nameTextField.stringValue = trigger.name ?: @"";
    const NSInteger i = [_triggers indexOfObjectPassingTest:^BOOL(Trigger * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj isKindOfClass:trigger.class];
    }];
    assert(i != NSNotFound);
    _enabledButton.state = trigger.disabled ? NSControlStateValueOff : NSControlStateValueOn;
    _instantButton.state = trigger.partialLine ? NSControlStateValueOn : NSControlStateValueOff;
    [_actionButton selectItemAtIndex:i];
    [self updateCustomViewForTrigger:trigger value:trigger.param];
    _visualizationViewController.regex = _regex ?: @"";
}

- (void)loadView {
    [self createViews];
    [self setupConstraints];
}

- (void)createViews {
    // Create main view
    NSView *mainView = [[NSView alloc] init];
    self.view = mainView;
    
    // Create vertical stack view
    NSStackView *stackView = [[NSStackView alloc] init];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeading;
    stackView.spacing = 8;
    [mainView addSubview:stackView];
    
    // Match type selector row (browser mode only)
    if (_browserMode) {
        NSView *matchTypeRow = [self createMatchTypeRow];
        [stackView addArrangedSubview:matchTypeRow];
    }
    
    // Regular Expression row
    NSView *regexRow = [self createRowWithLabelText:@"Regular Expression:" hasVisualizationButton:YES];
    [stackView addArrangedSubview:regexRow];
    
    // Name row
    NSView *nameRow = [self createRowWithLabelText:@"Name:" hasVisualizationButton:NO];
    [stackView addArrangedSubview:nameRow];
    
    // Buttons row
    NSView *buttonsRow = [self createButtonsRow];
    [stackView addArrangedSubview:buttonsRow];
    
    // Action row
    NSView *actionRow = [self createActionRow];
    [stackView addArrangedSubview:actionRow];
    
    // Param container - create a wrapper view for right alignment
    NSView *paramWrapperView = [[NSView alloc] init];
    paramWrapperView.translatesAutoresizingMaskIntoConstraints = NO;
    
    _paramContainerView = [[NSView alloc] init];
    _paramContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [paramWrapperView addSubview:_paramContainerView];
    
    // Right-align the param container and fix its width
    [paramWrapperView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                 attribute:NSLayoutAttributeTrailing
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:paramWrapperView
                                                                 attribute:NSLayoutAttributeTrailing
                                                                multiplier:1.0
                                                                  constant:0]];
    [paramWrapperView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                 attribute:NSLayoutAttributeWidth
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:nil
                                                                 attribute:NSLayoutAttributeNotAnAttribute
                                                                multiplier:1.0
                                                                  constant:319]];
    [paramWrapperView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                 attribute:NSLayoutAttributeTop
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:paramWrapperView
                                                                 attribute:NSLayoutAttributeTop
                                                                multiplier:1.0
                                                                  constant:0]];
    [paramWrapperView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                 attribute:NSLayoutAttributeBottom
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:paramWrapperView
                                                                 attribute:NSLayoutAttributeBottom
                                                                multiplier:1.0
                                                                  constant:0]];
    
    [stackView addArrangedSubview:paramWrapperView];
    
    // OK/Cancel buttons row
    NSView *okCancelRow = [self createOkCancelRow];
    [stackView addArrangedSubview:okCancelRow];
    
    // Store the stack view for constraints
    [mainView addConstraint:[NSLayoutConstraint constraintWithItem:stackView
                                                         attribute:NSLayoutAttributeTop
                                                         relatedBy:NSLayoutRelationEqual
                                                            toItem:mainView
                                                         attribute:NSLayoutAttributeTop
                                                        multiplier:1.0
                                                          constant:20]];
    [mainView addConstraint:[NSLayoutConstraint constraintWithItem:stackView
                                                         attribute:NSLayoutAttributeLeading
                                                         relatedBy:NSLayoutRelationEqual
                                                            toItem:mainView
                                                         attribute:NSLayoutAttributeLeading
                                                        multiplier:1.0
                                                          constant:20]];
    [mainView addConstraint:[NSLayoutConstraint constraintWithItem:stackView
                                                         attribute:NSLayoutAttributeTrailing
                                                         relatedBy:NSLayoutRelationEqual
                                                            toItem:mainView
                                                         attribute:NSLayoutAttributeTrailing
                                                        multiplier:1.0
                                                          constant:-20]];
    [mainView addConstraint:[NSLayoutConstraint constraintWithItem:stackView
                                                         attribute:NSLayoutAttributeBottom
                                                         relatedBy:NSLayoutRelationEqual
                                                            toItem:mainView
                                                         attribute:NSLayoutAttributeBottom
                                                        multiplier:1.0
                                                          constant:-20]];
}

- (NSView *)createRowWithLabelText:(NSString *)labelText hasVisualizationButton:(BOOL)hasVisualizationButton {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create label
    NSTextField *label = [[NSTextField alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = labelText;
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    label.usesSingleLineMode = YES;
    [row addSubview:label];
    
    // Create text field
    NSTextField *textField = [[NSTextField alloc] init];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    textField.bordered = YES;
    textField.editable = YES;
    textField.delegate = self;
    [row addSubview:textField];
    
    if ([labelText isEqualToString:@"Regular Expression:"]) {
        _regexTextField = textField;
    } else if ([labelText isEqualToString:@"Name:"]) {
        _nameTextField = textField;
    }
    
    // Add visualization button if needed
    if (hasVisualizationButton) {
        _toggleVisualizationButton = [[NSButton alloc] init];
        _toggleVisualizationButton.translatesAutoresizingMaskIntoConstraints = NO;
        _toggleVisualizationButton.bezelStyle = NSBezelStyleRounded;
        _toggleVisualizationButton.bordered = YES;
        _toggleVisualizationButton.image = [NSImage it_imageForSymbolName:@"flowchart"
                                                  accessibilityDescription:@"Show visualization"
                                                         fallbackImageName:@"flowchart"
                                                                  forClass:[self class]];
        _toggleVisualizationButton.target = self;
        _toggleVisualizationButton.action = @selector(toggleVisualization:);
        [row addSubview:_toggleVisualizationButton];
        
        // Constraints for row with visualization button
        [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                       attribute:NSLayoutAttributeLeading
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeLeading
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                       attribute:NSLayoutAttributeWidth
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:kLabelWidth]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                       attribute:NSLayoutAttributeCenterY
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeCenterY
                                                      multiplier:1.0
                                                        constant:0]];
        
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeLeading
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:label
                                                       attribute:NSLayoutAttributeTrailing
                                                      multiplier:1.0
                                                        constant:6]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeCenterY
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeCenterY
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeHeight
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:21]];
        
        [row addConstraint:[NSLayoutConstraint constraintWithItem:_toggleVisualizationButton
                                                       attribute:NSLayoutAttributeLeading
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:textField
                                                       attribute:NSLayoutAttributeTrailing
                                                      multiplier:1.0
                                                        constant:6]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:_toggleVisualizationButton
                                                       attribute:NSLayoutAttributeTrailing
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeTrailing
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:_toggleVisualizationButton
                                                       attribute:NSLayoutAttributeCenterY
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeCenterY
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:_toggleVisualizationButton
                                                       attribute:NSLayoutAttributeWidth
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:28]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:_toggleVisualizationButton
                                                       attribute:NSLayoutAttributeHeight
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:28]];
        
        [row addConstraint:[NSLayoutConstraint constraintWithItem:row
                                                       attribute:NSLayoutAttributeHeight
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:28]];
    } else {
        // Constraints for row without visualization button
        [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                       attribute:NSLayoutAttributeLeading
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeLeading
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                       attribute:NSLayoutAttributeWidth
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:kLabelWidth]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                       attribute:NSLayoutAttributeCenterY
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeCenterY
                                                      multiplier:1.0
                                                        constant:0]];
        
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeLeading
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:label
                                                       attribute:NSLayoutAttributeTrailing
                                                      multiplier:1.0
                                                        constant:6]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeTrailing
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeTrailing
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeCenterY
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:row
                                                       attribute:NSLayoutAttributeCenterY
                                                      multiplier:1.0
                                                        constant:0]];
        [row addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                       attribute:NSLayoutAttributeHeight
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:21]];
        
        [row addConstraint:[NSLayoutConstraint constraintWithItem:row
                                                       attribute:NSLayoutAttributeHeight
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:nil
                                                       attribute:NSLayoutAttributeNotAnAttribute
                                                      multiplier:1.0
                                                        constant:21]];
    }
    
    return row;
}

- (NSView *)createMatchTypeRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create label
    NSTextField *label = [[NSTextField alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = @"Match Against:";
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    label.usesSingleLineMode = YES;
    [row addSubview:label];
    
    // Create popup button for match type
    _matchTypeButton = [[NSPopUpButton alloc] init];
    _matchTypeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_matchTypeButton addItemWithTitle:@"URL"];
    [_matchTypeButton addItemWithTitle:@"Page Content"];
    _matchTypeButton.target = self;
    _matchTypeButton.action = @selector(matchTypeDidChange:);
    [row addSubview:_matchTypeButton];
    
    // Constraints
    [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeLeading
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                   attribute:NSLayoutAttributeWidth
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:kLabelWidth]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_matchTypeButton
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:label
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:6]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_matchTypeButton
                                                   attribute:NSLayoutAttributeTrailing
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_matchTypeButton
                                                   attribute:NSLayoutAttributeFirstBaseline
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:label
                                                   attribute:NSLayoutAttributeFirstBaseline
                                                  multiplier:1.0
                                                    constant:0]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:row
                                                   attribute:NSLayoutAttributeHeight
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:23]];
    
    return row;
}

- (NSView *)createButtonsRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    
    _instantButton = [[NSButton alloc] init];
    _instantButton.translatesAutoresizingMaskIntoConstraints = NO;
    _instantButton.buttonType = NSButtonTypeSwitch;
    _instantButton.title = @"Instant";
    _instantButton.target = self;
    _instantButton.action = @selector(instantDidChange:);
    [row addSubview:_instantButton];
    
    _enabledButton = [[NSButton alloc] init];
    _enabledButton.translatesAutoresizingMaskIntoConstraints = NO;
    _enabledButton.buttonType = NSButtonTypeSwitch;
    _enabledButton.title = @"Enabled";
    _enabledButton.target = self;
    _enabledButton.action = @selector(enabledDidChange:);
    [row addSubview:_enabledButton];
    
    _updateProfileButton = [[NSButton alloc] init];
    _updateProfileButton.translatesAutoresizingMaskIntoConstraints = NO;
    _updateProfileButton.buttonType = NSButtonTypeSwitch;
    _updateProfileButton.title = @"Update Profile";
    [row addSubview:_updateProfileButton];
    
    // Add leading spacer to align with text fields
    NSView *spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:spacer];
    
    // Constraints
    [row addConstraint:[NSLayoutConstraint constraintWithItem:spacer
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeLeading
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:spacer
                                                   attribute:NSLayoutAttributeWidth
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:kLabelWidth + 6]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_instantButton
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:spacer
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_enabledButton
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:_instantButton
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:6]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_updateProfileButton
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:_enabledButton
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:6]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_instantButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_enabledButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_updateProfileButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:row
                                                   attribute:NSLayoutAttributeHeight
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:18]];
    
    return row;
}

- (NSView *)createActionRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create label
    NSTextField *label = [[NSTextField alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = @"Action:";
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    label.usesSingleLineMode = YES;
    [row addSubview:label];
    
    // Create popup button
    _actionButton = [[NSPopUpButton alloc] init];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.target = self;
    _actionButton.action = @selector(selectionDidChange:);
    [row addSubview:_actionButton];
    
    // Constraints
    [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeLeading
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                   attribute:NSLayoutAttributeWidth
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:kLabelWidth]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:label
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_actionButton
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:label
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:6]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_actionButton
                                                   attribute:NSLayoutAttributeTrailing
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_actionButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:row
                                                   attribute:NSLayoutAttributeHeight
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:25]];
    
    return row;
}

- (NSView *)createOkCancelRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    
    _cancelButton = [[NSButton alloc] init];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.bezelStyle = NSBezelStyleRounded;
    _cancelButton.title = @"Cancel";
    _cancelButton.target = self;
    _cancelButton.action = @selector(cancel:);
    _cancelButton.keyEquivalent = @"\e"; // Escape key
    [row addSubview:_cancelButton];
    
    _okButton = [[NSButton alloc] init];
    _okButton.translatesAutoresizingMaskIntoConstraints = NO;
    _okButton.bezelStyle = NSBezelStyleRounded;
    _okButton.title = @"OK";
    _okButton.target = self;
    _okButton.action = @selector(ok:);
    _okButton.keyEquivalent = @"\r"; // Return key
    [row addSubview:_okButton];
    
    // Constraints - buttons right-aligned
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_okButton
                                                   attribute:NSLayoutAttributeTrailing
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_cancelButton
                                                   attribute:NSLayoutAttributeTrailing
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:_okButton
                                                   attribute:NSLayoutAttributeLeading
                                                  multiplier:1.0
                                                    constant:-6]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_cancelButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_okButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:row
                                                   attribute:NSLayoutAttributeHeight
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:32]];
    
    return row;
}

- (void)setupConstraints {
    // Set up param container view constraints
    [_paramContainerView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                    attribute:NSLayoutAttributeHeight
                                                                    relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                       toItem:nil
                                                                    attribute:NSLayoutAttributeNotAnAttribute
                                                                   multiplier:1.0
                                                                     constant:21]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _regexTextField.stringValue = _regex;
    _nameTextField.stringValue = @"";
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

- (void)removeOkCancel {
    _okButton.hidden = YES;
    _cancelButton.hidden = YES;
    _updateProfileButton.hidden = YES;
}

- (__kindof Trigger *)firstTriggerOfClass:(Class)theClass {
    return [_triggers objectPassingTest:^BOOL(Trigger *element, NSUInteger index, BOOL *stop) {
        return [element isKindOfClass:theClass];
    }];
}

- (IBAction)toggleVisualization:(NSButton *)button {
    if (!_popover || !_popover.isShown) {
        [_popover close];
        _visualizationViewController = [[iTermRegexVisualizationViewController alloc] initWithRegex:_regexTextField.stringValue ?: @""
                                                                                            maxSize:button.window.screen.visibleFrame.size];
        NSPopover *popover = [[NSPopover alloc] init];
        popover.contentViewController = _visualizationViewController;
        popover.behavior = NSPopoverBehaviorApplicationDefined;
        [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMaxX];
        _popover = popover;

        button.image = [NSImage it_imageForSymbolName:@"flowchart.fill"
                             accessibilityDescription:@"Hide visualization"
                                    fallbackImageName:@"flowchart.fill"
                                             forClass:[self class]];
    } else {
        [_popover close];
        _popover = nil;
        button.image = [NSImage it_imageForSymbolName:@"flowchart"
              accessibilityDescription:@"Show visualization"
                     fallbackImageName:@"flowchart"
                              forClass:[self class]];
    }
}

- (IBAction)instantDidChange:(id)sender {
    if (_didChange) {
        _didChange();
    }
}

- (IBAction)enabledDidChange:(id)sender {
    if (_didChange) {
        _didChange();
    }
}

- (IBAction)selectionDidChange:(id)sender {
    [self updateCustomViewForTrigger:self.currentTrigger value:nil];
    if (_didChange) {
        _didChange();
    }
}

- (IBAction)matchTypeDidChange:(id)sender {
    _matchType = (iTermTriggerMatchType)_matchTypeButton.indexOfSelectedItem;
    if (_didChange) {
        _didChange();
    }
}

- (IBAction)ok:(id)sender {
    Trigger *trigger = [self currentTrigger];
    const BOOL instant = _instantButton.state == NSControlStateValueOn;
    const BOOL updateProfile = _updateProfileButton.state == NSControlStateValueOn;
    NSMutableDictionary *mutableTriggerDictionary = [@{ kTriggerActionKey: trigger.action,
                                                        kTriggerRegexKey: _regexTextField.stringValue,
                                                        kTriggerParameterKey: [[self currentTrigger] param] ?: @0,
                                                        kTriggerPartialLineKey: @(instant),
                                                        kTriggerDisabledKey: @NO,
                                                        kTriggerNameKey: _nameTextField.stringValue ?: [NSNull null] } mutableCopy];
    
    if (_browserMode) {
        mutableTriggerDictionary[kTriggerMatchTypeKey] = @(_matchType);
    }
    
    NSDictionary *triggerDictionary = [mutableTriggerDictionary dictionaryByRemovingNullValues];
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
                                                            size:NSMakeSize(320, 21)
                                                           value:value
                                                        receiver:self
                                             interpolatedStrings:_interpolatedStrings
                                                       tableView:nil
                                                     delegateOut:&delegateToSave
                                                     wellFactory:^CPKColorWell *(NSRect frame, NSColor *color) {
        CPKColorWell *well = [[CPKColorWell alloc] initWithFrame:frame colorSpace:[NSColorSpace it_defaultColorSpace]];
        well.noColorAllowed = YES;
        well.continuous = YES;
        well.color = color;
        well.target = self;
        well.action = @selector(colorWellDidChange:);
        return well;
    }];
    _savedDelegate = delegateToSave;

    NSPopUpButton *popup = [NSPopUpButton castFrom:view];
    
    // Remove existing param view
    [_paramView removeFromSuperview];
    
    // Remove existing height constraint if any
    for (NSLayoutConstraint *constraint in _paramContainerView.constraints) {
        if (constraint.firstAttribute == NSLayoutAttributeHeight && constraint.secondItem == nil) {
            [_paramContainerView removeConstraint:constraint];
            break;
        }
    }
    
    // Set appropriate height based on view type
    CGFloat height = popup ? 25 : 21;
    [_paramContainerView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                    attribute:NSLayoutAttributeHeight
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:nil
                                                                    attribute:NSLayoutAttributeNotAnAttribute
                                                                   multiplier:1.0
                                                                     constant:height]];
    
    if ([view conformsToProtocol:@protocol(iTermOptionallyBordered)]) {
        [(id<iTermOptionallyBordered>)view setOptionalBorderEnabled:YES];
    }

    _paramView = view;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [_paramContainerView addSubview:view];
    
    // Add constraints to fill the container
    [_paramContainerView addConstraint:[NSLayoutConstraint constraintWithItem:view
                                                                    attribute:NSLayoutAttributeTop
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:_paramContainerView
                                                                    attribute:NSLayoutAttributeTop
                                                                   multiplier:1.0
                                                                     constant:0]];
    [_paramContainerView addConstraint:[NSLayoutConstraint constraintWithItem:view
                                                                    attribute:NSLayoutAttributeLeading
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:_paramContainerView
                                                                    attribute:NSLayoutAttributeLeading
                                                                   multiplier:1.0
                                                                     constant:0]];
    [_paramContainerView addConstraint:[NSLayoutConstraint constraintWithItem:view
                                                                    attribute:NSLayoutAttributeTrailing
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:_paramContainerView
                                                                    attribute:NSLayoutAttributeTrailing
                                                                   multiplier:1.0
                                                                     constant:0]];
    [_paramContainerView addConstraint:[NSLayoutConstraint constraintWithItem:view
                                                                    attribute:NSLayoutAttributeBottom
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:_paramContainerView
                                                                    attribute:NSLayoutAttributeBottom
                                                                   multiplier:1.0
                                                                     constant:0]];
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
    if (_didChange) {
        _didChange();
    }
}

- (id)parameter {
    return self.currentTrigger.param;
}

- (NSString *)action {
    return NSStringFromClass([self.currentTrigger class]);
}

- (BOOL)enabled {
    return _enabledButton.state == NSControlStateValueOn;
}

- (BOOL)instant {
    return _instantButton.state == NSControlStateValueOn;
}

- (NSString *)name {
    return _nameTextField.stringValue;
}

- (iTermTriggerMatchType)matchType {
    return _matchType;
}

- (void)willHide {
    [_popover close];
    _popover = nil;
    _visualizationViewController = nil;
    _toggleVisualizationButton.image = [NSImage it_imageForSymbolName:@"flowchart"
                                             accessibilityDescription:@"Show visualization"
                                                    fallbackImageName:@"flowchart"
                                                             forClass:[self class]];
}

#pragma mark - iTermTriggerParameterController

- (void)parameterPopUpButtonDidChange:(id)sender {
    [[self currentTrigger] setParam:[[self currentTrigger] objectAtIndex:[sender indexOfSelectedItem]]];
    if (_didChange) {
        _didChange();
    }
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = [NSTextField castFrom:obj.object];
    NSString *param = self.currentTrigger.param;

    if (textField == _regexTextField) {
        _regex = [[textField stringValue] copy];
        _visualizationViewController.regex = _regex ?: @"";
    } else if (textField != _nameTextField) {
        if ([textField.identifier isEqual:kTwoPraramNameColumnIdentifier]) {
            iTermTuple<NSString *, NSString *> *pair = [iTermTwoParameterTriggerCodec tupleFromString:[NSString castFrom:param]];
            pair.firstObject = textField.stringValue;
            param = [iTermTwoParameterTriggerCodec stringFromTuple:pair];
        } else if ([textField.identifier isEqual:kTwoPraramValueColumnIdentifier]) {
            iTermTuple<NSString *, NSString *> *pair = [iTermTwoParameterTriggerCodec tupleFromString:[NSString castFrom:param]];
            pair.secondObject = textField.stringValue;
            param = [iTermTwoParameterTriggerCodec stringFromTuple:pair];
        } else {
            param = textField.stringValue ?: @"";
        }
        [[self currentTrigger] setParam:param];
    }
    if (_didChange) {
        _didChange();
    }
}

@end
