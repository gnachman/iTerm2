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
    NSTextField *_jobTextField;
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
    iTermEventTriggerParameterView *_eventParamView;
    NSView *_regexRow;
    NSView *_eventParamRow;
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
    CGFloat height = browserMode ? 306 : 237;  // Extra 33 for match type row + 36 for content regex row + 29 for job row
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
    _jobTextField.stringValue = trigger.job ?: @"";
    const NSInteger prototypeIndex = [_prototypes indexOfObjectPassingTest:^BOOL(Trigger * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj isKindOfClass:trigger.class];
    }];
    _enabledButton.state = trigger.disabled ? NSControlStateValueOff : NSControlStateValueOn;
    _instantButton.state = trigger.partialLine ? NSControlStateValueOn : NSControlStateValueOff;
    // prototypeIndex == NSNotFound can happen if you have a trigger of the wrong browser/terminal mode or a trigger from a future version of the app.
    if (prototypeIndex != NSNotFound) {
        // Find the menu item with matching tag (since filtering may cause popup indices to differ from prototype indices)
        NSInteger itemIndex = [_actionButton.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger idx, BOOL *stop) {
            return item.tag == prototypeIndex;
        }];
        if (itemIndex != NSNotFound) {
            [_actionButton selectItemAtIndex:itemIndex];
        }
    }
    _currentTrigger = [Trigger triggerFromUntrustedDict:trigger.dictionaryValue];
    ITAssertWithMessage(_currentTrigger != nil, @"Failed with %@", trigger.dictionaryValue);  // If this fails then a trigger is not round-tripping to its dictionary representation.
    [self updateCustomViewForTrigger:_currentTrigger value:_currentTrigger.param];
    _visualizationViewController.regex = _regex ?: @"";
    _contentRegexVisualizationViewController.regex = _contentRegex ?: @"";
    _matchType = trigger.matchType;

    // Update match type button with types allowed by this trigger
    [self updateMatchTypeButtonForTrigger:trigger];

    [_matchTypeButton selectItemWithTag:_matchType];
    if (_browserMode) {
        [self updateContentRegexVisibility];
        _matchTypeButton.enabled = (trigger.allowedMatchTypes.count > 1);
    } else {
        [self updateEventTriggerVisibility];
        // Filter action popup based on current match type
        [self updateActionButtonForMatchType];
        // Re-select the correct action after filtering
        if (prototypeIndex != NSNotFound) {
            NSInteger itemIndex = [_actionButton.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger idx, BOOL *stop) {
                return item.tag == prototypeIndex;
            }];
            if (itemIndex != NSNotFound) {
                [_actionButton selectItemAtIndex:itemIndex];
            }
        }
        // Set the event params if this is an event trigger
        if (iTermTriggerMatchTypeIsEvent(_matchType) && trigger.eventParams) {
            _eventParamView.eventParams = trigger.eventParams;
        }
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
    stackView.detachesHiddenViews = YES;
    [mainView addSubview:stackView];
    
    // Match type selector row
    NSView *matchTypeRow = [self createMatchTypeRow];
    [stackView addArrangedSubview:matchTypeRow];

    // Regular Expression row
    _regexRow = [self createRowWithLabelText:@"Regular Expression:" hasVisualizationButton:YES];
    [stackView addArrangedSubview:_regexRow];

    // Event parameter row (hidden by default)
    _eventParamRow = [self createEventParamRow];
    _eventParamRow.hidden = YES;
    [stackView addArrangedSubview:_eventParamRow];
    
    // Content Regular Expression row (browser mode only)
    if (_browserMode) {
        NSView *contentRegexRow = [self createContentRegexRow];
        [stackView addArrangedSubview:contentRegexRow];
    }
    
    // Name row
    NSView *nameRow = [self createRowWithLabelText:@"Name:" hasVisualizationButton:NO];
    [stackView addArrangedSubview:nameRow];

    // Job row
    NSView *jobRow = [self createRowWithLabelText:@"Job:" hasVisualizationButton:NO];
    [stackView addArrangedSubview:jobRow];

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
    } else if ([labelText isEqualToString:@"Job:"]) {
        _jobTextField = textField;
        _jobTextField.placeholderString = @"Trigger enabled only for this job (e.g., emacs)";
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
    [_matchTypeButton it_addItemWithTitle:@"Regular Expression" tag:iTermTriggerMatchTypeRegex];

    if (_browserMode) {
        // Browser-specific match types
        [_matchTypeButton it_addItemWithTitle:@"URL" tag:iTermTriggerMatchTypeURLRegex];
        [_matchTypeButton it_addItemWithTitle:@"Page Content" tag:iTermTriggerMatchTypePageContentRegex];
    } else {
        // Terminal-specific event types, sorted alphabetically by display name
        [[_matchTypeButton menu] addItem:[NSMenuItem separatorItem]];
        NSArray<NSNumber *> *sortedEventTypes = [[iTermEventTriggerMatchTypeHelper allEventTypes] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            NSString *titleA = [iTermEventTriggerMatchTypeHelper displayNameFor:(iTermTriggerMatchType)a.integerValue];
            NSString *titleB = [iTermEventTriggerMatchTypeHelper displayNameFor:(iTermTriggerMatchType)b.integerValue];
            return [titleA localizedCaseInsensitiveCompare:titleB];
        }];
        for (NSNumber *typeNum in sortedEventTypes) {
            iTermTriggerMatchType type = (iTermTriggerMatchType)typeNum.integerValue;
            NSString *title = [iTermEventTriggerMatchTypeHelper displayNameFor:type];
            [_matchTypeButton it_addItemWithTitle:title tag:type];
        }
    }

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

- (NSView *)createEventParamRow {
    NSView *row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // Create label
    NSTextField *label = [[NSTextField alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = @"Parameters:";
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    label.usesSingleLineMode = YES;
    [row addSubview:label];

    // Create event parameter view
    _eventParamView = [[iTermEventTriggerParameterView alloc] initWithFrame:NSZeroRect];
    _eventParamView.translatesAutoresizingMaskIntoConstraints = NO;
    __weak __typeof(self) weakSelf = self;
    _eventParamView.onParametersChanged = ^{
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf->_didChange) {
            strongSelf->_didChange();
        }
    };
    [row addSubview:_eventParamView];

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
                                                    attribute:NSLayoutAttributeFirstBaseline
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:_eventParamView
                                                    attribute:NSLayoutAttributeFirstBaseline
                                                   multiplier:1.0
                                                     constant:0]];

    [row addConstraint:[NSLayoutConstraint constraintWithItem:_eventParamView
                                                    attribute:NSLayoutAttributeLeading
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:label
                                                    attribute:NSLayoutAttributeTrailing
                                                   multiplier:1.0
                                                     constant:6]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_eventParamView
                                                    attribute:NSLayoutAttributeTrailing
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:row
                                                    attribute:NSLayoutAttributeTrailing
                                                   multiplier:1.0
                                                     constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_eventParamView
                                                    attribute:NSLayoutAttributeTop
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:row
                                                    attribute:NSLayoutAttributeTop
                                                   multiplier:1.0
                                                     constant:0]];
    [row addConstraint:[NSLayoutConstraint constraintWithItem:_eventParamView
                                                    attribute:NSLayoutAttributeBottom
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:row
                                                    attribute:NSLayoutAttributeBottom
                                                   multiplier:1.0
                                                     constant:0]];

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
        _actionButton.lastItem.tag = idx;  // Store prototype index in tag for later lookup
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
    // Preserve the current match type and event params - action change doesn't affect match type options
    NSDictionary *savedEventParams = nil;
    if (iTermTriggerMatchTypeIsEvent(_matchType) && _eventParamView) {
        savedEventParams = [_eventParamView.eventParams copy];
    }

    Trigger *prototype = [self currentPrototype];

    NSMutableDictionary *dict = prototype.dictionaryValue.mutableCopy;
    dict[kTriggerRegexKey] = _regexTextField.stringValue ?: @"";
    dict[kTriggerNameKey] = _nameTextField.stringValue ?: @"";
    dict[kTriggerMatchTypeKey] = @(_matchType);
    if (savedEventParams.count > 0) {
        dict[kTriggerEventParamsKey] = savedEventParams;
    }
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
    [self updateEventTriggerVisibility];
    [self updateActionButtonForMatchType];
    if (_didChange) {
        _didChange();
    }
}

- (void)updateActionButtonForMatchType {
    if (_browserMode) {
        return;
    }

    // Remember the currently selected action class
    Trigger *currentPrototype = [self currentPrototype];
    Class currentClass = currentPrototype.class;

    // Rebuild the action popup with only compatible actions
    [_actionButton removeAllItems];

    NSInteger indexToSelect = 0;
    NSInteger currentIndex = 0;

    for (Trigger *prototype in _prototypes) {
        NSSet<NSNumber *> *allowedTypes = prototype.allowedMatchTypes;
        if ([allowedTypes containsObject:@(_matchType)]) {
            [_actionButton addItemWithTitle:[prototype.class title]];
            // Track the index of the item
            NSMenuItem *item = _actionButton.lastItem;
            item.tag = currentIndex;

            if (prototype.class == currentClass) {
                indexToSelect = _actionButton.numberOfItems - 1;
            }
        }
        currentIndex++;
    }

    // Select the appropriate action
    if (_actionButton.numberOfItems > 0) {
        [_actionButton selectItemAtIndex:indexToSelect];

        // Update the trigger view for the selected action
        Trigger *selectedPrototype = _prototypes[_actionButton.selectedItem.tag];
        // If we already have a current trigger of the same class, preserve its param value
        id paramValue = ([_currentTrigger isKindOfClass:selectedPrototype.class]) ? _currentTrigger.param : selectedPrototype.param;
        [self updateCustomViewForTrigger:selectedPrototype value:paramValue];
        if (![_currentTrigger isKindOfClass:selectedPrototype.class]) {
            _currentTrigger = [Trigger triggerFromUntrustedDict:selectedPrototype.dictionaryValue];
        }
    }
}

- (void)updateEventTriggerVisibility {
    BOOL isEventTrigger = iTermTriggerMatchTypeIsEvent(_matchType);
    _regexRow.hidden = isEventTrigger;
    _eventParamRow.hidden = !isEventTrigger;

    // Instant (partial line) doesn't apply to event triggers
    _instantButton.enabled = !isEventTrigger;
    if (isEventTrigger) {
        _instantButton.state = NSControlStateValueOff;
        [_eventParamView configureForMatchType:_matchType];
    }
    // Job started/ended own the job-name selection via their own
    // parameter (the global "job" filter would be redundant and
    // confusing). Disable + clear the placeholder so the field
    // reads as inert.
    BOOL jobFieldRedundant = (_matchType == iTermTriggerMatchTypeEventJobStarted ||
                              _matchType == iTermTriggerMatchTypeEventJobEnded);
    _jobTextField.enabled = !jobFieldRedundant;
    if (jobFieldRedundant) {
        _jobTextField.placeholderString = @"Set job above";
        // Clear so we don't serialize a stale trigger.job from a
        // previously-selected match type. The job-started/ended
        // evaluator ignores trigger.job entirely (it reads from
        // eventParams["jobName"]), but writing dead data here
        // would confuse future callers.
        _jobTextField.stringValue = @"";
    } else {
        _jobTextField.placeholderString = @"Trigger enabled only for this job (e.g., emacs)";
    }
}

- (void)updateMatchTypeButtonForTrigger:(Trigger *)trigger {
    if (_browserMode) {
        // Browser mode doesn't change match types based on action
        return;
    }

    // Clear the popup
    [_matchTypeButton removeAllItems];

    // Always add regex
    [_matchTypeButton it_addItemWithTitle:@"Regular Expression" tag:iTermTriggerMatchTypeRegex];

    // Add all event types, sorted alphabetically by display name
    NSArray<NSNumber *> *sortedEventTypes = [[iTermEventTriggerMatchTypeHelper allEventTypes] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSString *titleA = [iTermEventTriggerMatchTypeHelper displayNameFor:(iTermTriggerMatchType)a.integerValue];
        NSString *titleB = [iTermEventTriggerMatchTypeHelper displayNameFor:(iTermTriggerMatchType)b.integerValue];
        return [titleA localizedCaseInsensitiveCompare:titleB];
    }];

    [[_matchTypeButton menu] addItem:[NSMenuItem separatorItem]];
    for (NSNumber *typeNum in sortedEventTypes) {
        iTermTriggerMatchType type = (iTermTriggerMatchType)typeNum.integerValue;
        NSString *title = [iTermEventTriggerMatchTypeHelper displayNameFor:type];
        [_matchTypeButton it_addItemWithTitle:title tag:type];
    }

    [_matchTypeButton selectItemWithTag:_matchType];
    [self updateEventTriggerVisibility];
}

- (IBAction)ok:(id)sender {
    Trigger *trigger = _currentTrigger;
    const BOOL instant = _instantButton.state == NSControlStateValueOn;
    const BOOL updateProfile = _updateProfileButton.state == NSControlStateValueOn;
    const BOOL isEventTrigger = iTermTriggerMatchTypeIsEvent(_matchType);

    NSMutableDictionary *mutableTriggerDictionary = [@{ kTriggerActionKey: trigger.action,
                                                        kTriggerRegexKey: isEventTrigger ? @"" : _regexTextField.stringValue,
                                                        kTriggerContentRegexKey: _contentRegexTextField.stringValue ?: @"",
                                                        kTriggerParameterKey: [trigger param] ?: @0,
                                                        kTriggerPartialLineKey: @(instant),
                                                        kTriggerDisabledKey: @NO,
                                                        kTriggerMatchTypeKey: @(_matchType),
                                                        kTriggerNameKey: _nameTextField.stringValue ?: [NSNull null],
                                                        kTriggerJobKey: _jobTextField.stringValue.length > 0 ? _jobTextField.stringValue : [NSNull null] } mutableCopy];

    // Add event params for event triggers
    if (isEventTrigger && _eventParamView) {
        NSDictionary *eventParams = _eventParamView.eventParams;
        if (eventParams.count > 0) {
            mutableTriggerDictionary[kTriggerEventParamsKey] = eventParams;
        }
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
    // Use tag which stores the index into _prototypes (may differ from popup index due to filtering)
    NSMenuItem *selectedItem = _actionButton.selectedItem;
    if (selectedItem && selectedItem.tag >= 0 && selectedItem.tag < (NSInteger)_prototypes.count) {
        return _prototypes[selectedItem.tag];
    }
    // Fallback to index (for initial state or browser mode)
    const NSInteger index = [_actionButton indexOfSelectedItem];
    if (index >= 0 && index < (NSInteger)_prototypes.count) {
        return _prototypes[index];
    }
    return _prototypes.firstObject;
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
    CGFloat height = (popup || [trigger paramIsComboBoxAndTwoColorWells]) ? 25 : 21;
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

- (NSString *)job {
    NSString *value = _jobTextField.stringValue;
    return value.length > 0 ? value : nil;
}

- (iTermTriggerMatchType)matchType {
    return _matchType;
}

- (NSDictionary<NSString *, id> *)eventParams {
    if (iTermTriggerMatchTypeIsEvent(_matchType) && _eventParamView) {
        return _eventParamView.eventParams;
    }
    return nil;
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
    if ([sender isKindOfClass:[NSComboBox class]]) {
        NSComboBox *comboBox = sender;
        // objectValueOfSelectedItem has the newly picked value;
        // stringValue hasn't been updated yet at action-send time.
        NSString *value = [comboBox objectValueOfSelectedItem] ?: comboBox.stringValue;
        id updated = [_currentTrigger paramByReplacingComboBoxValue:value
                                                            inParam:_currentTrigger.param];
        [_currentTrigger setParam:updated];
        if (_didChange) {
            _didChange();
        }
        return;
    }
    const NSUInteger i = [sender indexOfSelectedItem];
    [_currentTrigger setParam:[_currentTrigger objectAtIndex:i]];
    if (_didChange) {
        _didChange();
    }
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    NSComboBox *comboBox = notification.object;
    NSString *value = [comboBox objectValueOfSelectedItem];
    if (value) {
        id updated = [_currentTrigger paramByReplacingComboBoxValue:value
                                                            inParam:_currentTrigger.param];
        [_currentTrigger setParam:updated];
        if (_didChange) {
            _didChange();
        }
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
    } else if (textField != _nameTextField && textField != _jobTextField) {
        if ([textField.identifier isEqual:kStatusTextComboBoxIdentifier]) {
            param = [_currentTrigger paramByReplacingComboBoxValue:textField.stringValue
                                                           inParam:param];
        } else if ([textField.identifier isEqual:kTwoPraramNameColumnIdentifier]) {
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
