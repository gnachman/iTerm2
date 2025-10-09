//
//  iTermAddTriggerViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import "iTermAddTriggerViewController.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

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
#import "NSPopUpButton+iTerm.h"
#import "Trigger.h"
#import "TriggerController.h"

#import <ColorPicker/ColorPicker.h>

static const CGFloat kLabelWidth = 124;

@interface iTermAddTriggerViewController()<iTermTriggerParameterController>
@end

@implementation iTermAddTriggerViewController {
    NSTextField *_regexTextField;
    NSTextField *_contentRegexTextField;
    NSTextField *_nameTextField;
    NSTextField *_regexLabel;
    NSPopUpButton *_actionButton;
    NSView *_paramContainerView;
    NSButton *_instantButton;
    NSButton *_updateProfileButton;
    NSButton *_okButton;
    NSButton *_cancelButton;
    NSButton *_enabledButton;
    NSButton *_toggleVisualizationButton;
    NSButton *_contentRegexVisualizationButton;
    NSPopUpButton *_matchTypeButton;
    NSView *_performanceGraphContainer;
    NSView *_performanceRow;
    NSView *_okCancelRow;
    
    NSArray<Trigger *> *_prototypes;
    Trigger *_currentTrigger;
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
    iTermRegexVisualizationViewController *_contentRegexVisualizationViewController;
    NSPopover *_popover;
    NSPopover *_contentRegexPopover;
    NSString *_contentRegex;
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
                                                                                  matchType:iTermTriggerMatchTypeRegex
                                                                                      regex:regex
                                                                               contentRegex:nil
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
    CGFloat height = browserMode ? 277 : 208;  // Extra 33 points for match type row + 36 points for content regex row
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
                   matchType:(iTermTriggerMatchType)matchType
                       regex:(NSString *)regex
                contentRegex:(NSString * _Nullable)contentRegex
         interpolatedStrings:(BOOL)interpolatedStrings
            defaultTextColor:(NSColor *)defaultTextColor
      defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                 browserMode:(BOOL)browserMode
                  completion:(void (^)(NSDictionary * _Nullable, BOOL))completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _regex = [regex copy];
        _contentRegex = [contentRegex copy];
        _contentRegex = nil;
        _interpolatedStrings = interpolatedStrings;
        _defaultTextColor = defaultTextColor;
        _defaultBackgroundColor = defaultBackgroundColor;
        _completion = [completion copy];
        _browserMode = browserMode;
        _matchType = matchType;
    }
    return self;
}

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _regex = @"";
        _contentRegex = nil;
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
        _contentRegex = nil;
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
    _regex = [trigger.regex copy] ?: @"";
    _contentRegex = [trigger.contentRegex copy];
    _regexTextField.stringValue = _regex;
    _contentRegexTextField.stringValue = _contentRegex ?: @"";
    _nameTextField.stringValue = trigger.name ?: @"";
    const NSInteger i = [_prototypes indexOfObjectPassingTest:^BOOL(Trigger * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj isKindOfClass:trigger.class];
    }];
    _enabledButton.state = trigger.disabled ? NSControlStateValueOff : NSControlStateValueOn;
    _instantButton.state = trigger.partialLine ? NSControlStateValueOn : NSControlStateValueOff;
    // i == NSNotFound can happen if you have a trigger of the wrong browser/terminal mode or a trigger from a future version of the app.
    if (i != NSNotFound) {
        [_actionButton selectItemAtIndex:i];
    }
    _currentTrigger = [Trigger triggerFromUntrustedDict:trigger.dictionaryValue];
    ITAssertWithMessage(_currentTrigger != nil, @"Failed with %@", trigger.dictionaryValue);  // If this fails then a trigger is not round-tripping to its dictionary representation.
    [self updateCustomViewForTrigger:_currentTrigger value:_currentTrigger.param];
    _visualizationViewController.regex = _regex ?: @"";
    _contentRegexVisualizationViewController.regex = _contentRegex ?: @"";
    _matchType = trigger.matchType;
    if (_browserMode) {
        [_matchTypeButton selectItemWithTag:_matchType];
        [self updateContentRegexVisibility];
        _matchTypeButton.enabled = (trigger.allowedMatchTypes.count > 1);
    }
    
    // Show or hide the performance graph row based on whether the trigger has a performance histogram
    BOOL shouldShowGraph = trigger.performanceHistogram.count > 0;

    if (@available(macOS 13, *)) {
        // Remove any existing chart view
        [_performanceGraphContainer.subviews.firstObject removeFromSuperview];
        
        if (shouldShowGraph) {
            _performanceRow.hidden = NO;
            
            iTermHistogram *histogram = trigger.performanceHistogram;
            NSView *chart = [[iTermHistogramVisualizationView alloc] initWithHistogram:histogram];
            if (chart) {
                chart.translatesAutoresizingMaskIntoConstraints = NO;
                [_performanceGraphContainer addSubview:chart];
                
                // Set up constraints to fill the container
                [NSLayoutConstraint activateConstraints:@[
                    [chart.leadingAnchor constraintEqualToAnchor:_performanceGraphContainer.leadingAnchor],
                    [chart.trailingAnchor constraintEqualToAnchor:_performanceGraphContainer.trailingAnchor],
                    [chart.topAnchor constraintEqualToAnchor:_performanceGraphContainer.topAnchor],
                    [chart.bottomAnchor constraintEqualToAnchor:_performanceGraphContainer.bottomAnchor]
                ]];
            }
        } else {
            _performanceRow.hidden = YES;
        }
    } else {
        _performanceRow.hidden = YES;
    }
    
    // Force the view to re-layout after showing/hiding the graph row
    [self.view setNeedsLayout:YES];
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
    // I'm removing this for now because we don't have a trigger that allows multiple match types.
    //   if (_browserMode) {
    //        NSView *matchTypeRow = [self createMatchTypeRow];
    //        [stackView addArrangedSubview:matchTypeRow];
    //    }

    // Regular Expression row
    NSView *regexRow = [self createRowWithLabelText:@"Regular Expression:" hasVisualizationButton:YES];
    [stackView addArrangedSubview:regexRow];
    
    // Content Regular Expression row (browser mode only)
    if (_browserMode) {
        NSView *contentRegexRow = [self createContentRegexRow];
        [stackView addArrangedSubview:contentRegexRow];
    }
    
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
    
    // Left-align the param container to match other controls and stretch to trailing edge
    [paramWrapperView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                 attribute:NSLayoutAttributeLeading
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:paramWrapperView
                                                                 attribute:NSLayoutAttributeLeading
                                                                multiplier:1.0
                                                                  constant:kLabelWidth + 6]];
    [paramWrapperView addConstraint:[NSLayoutConstraint constraintWithItem:_paramContainerView
                                                                 attribute:NSLayoutAttributeTrailing
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:paramWrapperView
                                                                 attribute:NSLayoutAttributeTrailing
                                                                multiplier:1.0
                                                                  constant:0]];
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
    
    // Performance graph row with label (initially hidden)
    NSView *performanceRow = [[NSView alloc] init];
    performanceRow.translatesAutoresizingMaskIntoConstraints = NO;
    performanceRow.hidden = YES;
    
    // Create help button
    NSString *helpText = @"This histogram shows how much CPU time was used evaluating the regular expression for this trigger over the lifetime of the current terminal session. The X axis gives time in microseconds while the Y axis gives the number of samples which fell in that duration bucket. The vertical red line indicates the mean duration. You can use this to diagnose triggers that cause performance problems.";
    iTermPopoverHelpButton *helpButton = [[iTermPopoverHelpButton alloc] initWithHelpText:helpText];
    helpButton.translatesAutoresizingMaskIntoConstraints = NO;
    [performanceRow addSubview:helpButton];
    
    // Create label
    NSTextField *performanceLabel = [[NSTextField alloc] init];
    performanceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    performanceLabel.stringValue = @"CPU Time:";
    performanceLabel.editable = NO;
    performanceLabel.bordered = NO;
    performanceLabel.backgroundColor = [NSColor clearColor];
    performanceLabel.alignment = NSTextAlignmentRight;
    performanceLabel.lineBreakMode = NSLineBreakByClipping;
    performanceLabel.usesSingleLineMode = YES;
    [performanceRow addSubview:performanceLabel];
    
    // Create container for the chart
    _performanceGraphContainer = [[NSView alloc] init];
    _performanceGraphContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [performanceRow addSubview:_performanceGraphContainer];
    
    // Set up constraints for help button, label and container
    // Help button positioned just before the label
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:helpButton
                                                               attribute:NSLayoutAttributeTrailing
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceLabel
                                                               attribute:NSLayoutAttributeLeading
                                                              multiplier:1.0
                                                                constant:-4]];  // Small gap before "CPU Time:"
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:helpButton
                                                               attribute:NSLayoutAttributeCenterY
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceLabel
                                                               attribute:NSLayoutAttributeCenterY
                                                              multiplier:1.0
                                                                constant:0]];
    
    // Label uses intrinsic content size and is positioned at the right edge of the label area
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:performanceLabel
                                                               attribute:NSLayoutAttributeTrailing
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceRow
                                                               attribute:NSLayoutAttributeLeading
                                                              multiplier:1.0
                                                                constant:kLabelWidth]];
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:performanceLabel
                                                               attribute:NSLayoutAttributeTop
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceRow
                                                               attribute:NSLayoutAttributeTop
                                                              multiplier:1.0
                                                                constant:12]];  // Move down by 12 points
    
    // Set content hugging priority to make the label hug its content
    [performanceLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:_performanceGraphContainer
                                                               attribute:NSLayoutAttributeLeading
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceLabel
                                                               attribute:NSLayoutAttributeTrailing
                                                              multiplier:1.0
                                                                constant:6]];
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:_performanceGraphContainer
                                                               attribute:NSLayoutAttributeTrailing
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceRow
                                                               attribute:NSLayoutAttributeTrailing
                                                              multiplier:1.0
                                                                constant:0]];
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:_performanceGraphContainer
                                                               attribute:NSLayoutAttributeTop
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceRow
                                                               attribute:NSLayoutAttributeTop
                                                              multiplier:1.0
                                                                constant:0]];
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:_performanceGraphContainer
                                                               attribute:NSLayoutAttributeBottom
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:performanceRow
                                                               attribute:NSLayoutAttributeBottom
                                                              multiplier:1.0
                                                                constant:0]];
    
    // Height constraint for the row
    [performanceRow addConstraint:[NSLayoutConstraint constraintWithItem:performanceRow
                                                                attribute:NSLayoutAttributeHeight
                                                                relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                   toItem:nil
                                                                attribute:NSLayoutAttributeNotAnAttribute
                                                               multiplier:1.0
                                                                 constant:0]];
    
    // Store reference to the row for showing/hiding
    _performanceRow = performanceRow;
    
    [stackView addArrangedSubview:performanceRow];
    
    // Constrain performance row to fill the width of the stack view
    [stackView addConstraint:[NSLayoutConstraint constraintWithItem:performanceRow
                                                          attribute:NSLayoutAttributeLeading
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:stackView
                                                          attribute:NSLayoutAttributeLeading
                                                         multiplier:1.0
                                                           constant:0]];
    [stackView addConstraint:[NSLayoutConstraint constraintWithItem:performanceRow
                                                          attribute:NSLayoutAttributeTrailing
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:stackView
                                                          attribute:NSLayoutAttributeTrailing
                                                         multiplier:1.0
                                                           constant:0]];
    
    // OK/Cancel buttons row
    _okCancelRow = [self createOkCancelRow];
    [stackView addArrangedSubview:_okCancelRow];
    
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
        _regexLabel = label;
    } else if ([labelText isEqualToString:@"Name:"]) {
        _nameTextField = textField;
    }
    
    // Add visualization button if needed
    if (hasVisualizationButton) {
        _toggleVisualizationButton = [[NSButton alloc] init];
        _toggleVisualizationButton.translatesAutoresizingMaskIntoConstraints = NO;
        _toggleVisualizationButton.bezelStyle = NSBezelStyleRounded;
        _toggleVisualizationButton.bordered = YES;
        _toggleVisualizationButton.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchart)
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
    [_matchTypeButton it_addItemWithTitle:@"URL" tag:iTermTriggerMatchTypeURLRegex];
    [_matchTypeButton it_addItemWithTitle:@"Page Content" tag:iTermTriggerMatchTypePageContentRegex];
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

- (NSView *)createContentRegexRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create label
    NSTextField *label = [[NSTextField alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = @"Content Regex:";
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    label.usesSingleLineMode = YES;
    [row addSubview:label];
    
    // Create text field
    _contentRegexTextField = [[NSTextField alloc] init];
    _contentRegexTextField.translatesAutoresizingMaskIntoConstraints = NO;
    _contentRegexTextField.bordered = YES;
    _contentRegexTextField.editable = YES;
    _contentRegexTextField.delegate = self;
    [row addSubview:_contentRegexTextField];
    
    // Create visualization button
    _contentRegexVisualizationButton = [[NSButton alloc] init];
    _contentRegexVisualizationButton.translatesAutoresizingMaskIntoConstraints = NO;
    _contentRegexVisualizationButton.bezelStyle = NSBezelStyleRounded;
    _contentRegexVisualizationButton.bordered = YES;
    _contentRegexVisualizationButton.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchart)
                                                    accessibilityDescription:@"Show content regex visualization"
                                                           fallbackImageName:@"flowchart"
                                                                    forClass:[self class]];
    _contentRegexVisualizationButton.target = self;
    _contentRegexVisualizationButton.action = @selector(toggleContentRegexVisualization:);
    [row addSubview:_contentRegexVisualizationButton];
    
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
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexTextField
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:label
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:6]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexTextField
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexTextField
                                                   attribute:NSLayoutAttributeHeight
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:21]];
    
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexVisualizationButton
                                                   attribute:NSLayoutAttributeLeading
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:_contentRegexTextField
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:6]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexVisualizationButton
                                                   attribute:NSLayoutAttributeTrailing
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeTrailing
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexVisualizationButton
                                                   attribute:NSLayoutAttributeCenterY
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:row
                                                   attribute:NSLayoutAttributeCenterY
                                                  multiplier:1.0
                                                    constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexVisualizationButton
                                                   attribute:NSLayoutAttributeWidth
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:nil
                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                  multiplier:1.0
                                                    constant:28]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_contentRegexVisualizationButton
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
    if (_contentRegexTextField) {
        _contentRegexTextField.stringValue = _contentRegex ?: @"";
    }
    _nameTextField.stringValue = @"";
    _instantButton.state = [iTermUserDefaults addTriggerInstant] ? NSControlStateValueOn : NSControlStateValueOff;
    _updateProfileButton.state = [iTermUserDefaults addTriggerUpdateProfile] ? NSControlStateValueOn : NSControlStateValueOff;
    _prototypes = [[TriggerController triggerClassesForTerminal:!_browserMode] mapWithBlock:^id(Class triggerClass) {
        Trigger *trigger = [[triggerClass alloc] init];
        if (_regex) {
            trigger.regex = _regex;
        }
        return trigger;
    }];
    [_prototypes enumerateObjectsUsingBlock:^(Trigger *_Nonnull trigger, NSUInteger idx, BOOL * _Nonnull stop) {
        [trigger reloadData];
        [_actionButton addItemWithTitle:[trigger.class title]];
    }];

    // Select highlight with colors based on text.
    for (Class theClass in @[ [iTermHighlightLineTrigger class], [HighlightTrigger class] ]) {
        Trigger<iTermColorSettable> *trigger = [self prototypeOfClass:theClass];
        if (trigger) {
            [trigger setTextColor:_defaultTextColor];
            [trigger setBackgroundColor:_defaultBackgroundColor];
            [_actionButton selectItemAtIndex:[_prototypes indexOfObject:trigger]];
            [self setTrigger:trigger];
        } else {
            [_actionButton selectItemAtIndex:0];
        }
    }
    
    // Set up initial content regex visibility and hide instant button in browser mode
    if (_browserMode) {
        [self updateContentRegexVisibility];
        [self updateButtonLayoutForBrowserMode];
    }
}

- (void)removeOkCancel {
    [_okCancelRow removeFromSuperview];
    _okButton.hidden = YES;
    _cancelButton.hidden = YES;
    _updateProfileButton.hidden = YES;
}

- (__kindof Trigger *)prototypeOfClass:(Class)theClass {
    return [_prototypes objectPassingTest:^BOOL(Trigger *element, NSUInteger index, BOOL *stop) {
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

        button.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchartFill)
                             accessibilityDescription:@"Hide visualization"
                                    fallbackImageName:@"flowchart.fill"
                                             forClass:[self class]];
    } else {
        [_popover close];
        _popover = nil;
        button.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchart)
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
    Trigger *prototype = [self currentPrototype];
    NSMutableDictionary *dict = prototype.dictionaryValue.mutableCopy;
    dict[kTriggerRegexKey] = _regexTextField.stringValue ?: @"";
    dict[kTriggerNameKey] = _nameTextField.stringValue ?: @"";
    prototype = [Trigger triggerFromUntrustedDict:dict];
    assert(prototype != nil);
    [self setTrigger:prototype];
    if (_didChange) {
        _didChange();
    }
}

- (IBAction)matchTypeDidChange:(id)sender {
    _matchType = (iTermTriggerMatchType)_matchTypeButton.selectedTag;
    [self updateContentRegexVisibility];
    if (_didChange) {
        _didChange();
    }
}

- (IBAction)ok:(id)sender {
    Trigger *trigger = _currentTrigger;
    const BOOL instant = _instantButton.state == NSControlStateValueOn;
    const BOOL updateProfile = _updateProfileButton.state == NSControlStateValueOn;
    NSMutableDictionary *mutableTriggerDictionary = [@{ kTriggerActionKey: trigger.action,
                                                        kTriggerRegexKey: _regexTextField.stringValue,
                                                        kTriggerContentRegexKey: _contentRegexTextField.stringValue ?: @"",
                                                        kTriggerParameterKey: [trigger param] ?: @0,
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

- (Trigger *)currentPrototype {
    const NSInteger index = [_actionButton indexOfSelectedItem];
    return _prototypes[index];
}

- (void)updateCustomViewForTrigger:(Trigger *)trigger value:(id)value {
    id delegateToSave;
    NSView *view = [TriggerController viewForParameterForTrigger:trigger
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
    id<iTermColorSettable> trigger = (id)_currentTrigger;
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
    return _currentTrigger.param;
}

- (NSString *)action {
    return NSStringFromClass([_currentTrigger class]);
}

- (NSString *)contentRegex {
    return _contentRegex;
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
    _toggleVisualizationButton.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchart)
                                             accessibilityDescription:@"Show visualization"
                                                    fallbackImageName:@"flowchart"
                                                             forClass:[self class]];
    
    [_contentRegexPopover close];
    _contentRegexPopover = nil;
    _contentRegexVisualizationViewController = nil;
    if (_contentRegexVisualizationButton) {
        _contentRegexVisualizationButton.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchart)
                                                         accessibilityDescription:@"Show content regex visualization"
                                                                fallbackImageName:@"flowchart"
                                                                         forClass:[self class]];
    }
}

- (void)updateContentRegexVisibility {
    if (!_browserMode || !_contentRegexTextField) {
        return;
    }
    
    BOOL shouldShowContentRegex = (_matchType == iTermTriggerMatchTypePageContentRegex);
    _contentRegexTextField.superview.hidden = !shouldShowContentRegex;
    
    // Update the regex label text based on match type
    if (_regexLabel) {
        if (_matchType == iTermTriggerMatchTypePageContentRegex) {
            _regexLabel.stringValue = @"URL Regex:";
        } else {
            _regexLabel.stringValue = @"Regular Expression:";
        }
    }
}

- (IBAction)toggleContentRegexVisualization:(NSButton *)button {
    if (!_contentRegexPopover || !_contentRegexPopover.isShown) {
        [_contentRegexPopover close];
        _contentRegexVisualizationViewController = [[iTermRegexVisualizationViewController alloc] initWithRegex:_contentRegexTextField.stringValue ?: @""
                                                                                                        maxSize:button.window.screen.visibleFrame.size];
        NSPopover *popover = [[NSPopover alloc] init];
        popover.contentViewController = _contentRegexVisualizationViewController;
        popover.behavior = NSPopoverBehaviorApplicationDefined;
        [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMaxX];
        _contentRegexPopover = popover;

        button.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchartFill)
                             accessibilityDescription:@"Hide content regex visualization"
                                    fallbackImageName:@"flowchart.fill"
                                             forClass:[self class]];
    } else {
        [_contentRegexPopover close];
        _contentRegexPopover = nil;
        button.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFlowchart)
              accessibilityDescription:@"Show content regex visualization"
                     fallbackImageName:@"flowchart"
                              forClass:[self class]];
    }
}

- (void)updateButtonLayoutForBrowserMode {
    if (!_browserMode) {
        return;
    }
    
    // Hide the instant button
    _instantButton.hidden = YES;
    
    // Find and remove the existing leading constraint for the enabled button
    NSView *buttonsRow = _instantButton.superview;
    if (!buttonsRow) {
        return;
    }
    
    NSLayoutConstraint *enabledButtonLeadingConstraint = nil;
    for (NSLayoutConstraint *constraint in buttonsRow.constraints) {
        if (constraint.firstItem == _enabledButton && 
            constraint.firstAttribute == NSLayoutAttributeLeading &&
            constraint.secondItem == _instantButton &&
            constraint.secondAttribute == NSLayoutAttributeTrailing) {
            enabledButtonLeadingConstraint = constraint;
            break;
        }
    }
    
    if (enabledButtonLeadingConstraint) {
        [buttonsRow removeConstraint:enabledButtonLeadingConstraint];
        
        // Add new constraint connecting enabled button directly to spacer
        NSView *spacer = nil;
        for (NSView *subview in buttonsRow.subviews) {
            if (subview != _instantButton && subview != _enabledButton && subview != _updateProfileButton) {
                spacer = subview;
                break;
            }
        }
        
        if (spacer) {
            [buttonsRow addConstraint:[NSLayoutConstraint constraintWithItem:_enabledButton
                                                                   attribute:NSLayoutAttributeLeading
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:spacer
                                                                   attribute:NSLayoutAttributeTrailing
                                                                  multiplier:1.0
                                                                    constant:0]];
        }
    }
}

#pragma mark - iTermTriggerParameterController

- (void)parameterPopUpButtonDidChange:(id)sender {
    const NSUInteger i = [sender indexOfSelectedItem];
    [_currentTrigger setParam:[_currentTrigger objectAtIndex:i]];
    if (_didChange) {
        _didChange();
    }
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = [NSTextField castFrom:obj.object];
    NSString *param = _currentTrigger.param;

    if (textField == _regexTextField) {
        _regex = [[textField stringValue] copy];
        _visualizationViewController.regex = _regex ?: @"";
    } else if (textField == _contentRegexTextField) {
        _contentRegex = [[textField stringValue] copy];
        _contentRegexVisualizationViewController.regex = _contentRegex ?: @"";
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
        [_currentTrigger setParam:param];
    }
    if (_didChange) {
        _didChange();
    }
}

@end
