//
//  TriggerController.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "TriggerController.h"

#import "AlertTrigger.h"
#import "AnnotateTrigger.h"
#import "BellTrigger.h"
#import "BounceTrigger.h"
#import "CaptureTrigger.h"
#import "CoprocessTrigger.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermUserNotificationTrigger.h"
#import "HighlightTrigger.h"
#import "iTermSetTitleTrigger.h"
#import "ITAddressBookMgr.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermHighlightLineTrigger.h"
#import "iTermNoColorAccessoryButton.h"
#import "iTermOptionallyBordered.h"
#import "iTermProfilePreferences.h"
#import "iTermRPCTrigger.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermShellPromptTrigger.h"
#import "MarkTrigger.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"
#import "PasswordTrigger.h"
#import "ProfileModel.h"
#import "ScriptTrigger.h"
#import "SendTextTrigger.h"
#import "SetDirectoryTrigger.h"
#import "SetHostnameTrigger.h"
#import "StopTrigger.h"
#import "iTermHyperlinkTrigger.h"
#import "Trigger.h"
#import <ColorPicker/ColorPicker.h>

static NSString *const kiTermTriggerControllerPasteboardType =
    @"kiTermTriggerControllerPasteboardType";

static NSString *const kRegexColumnIdentifier = @"kRegexColumnIdentifier";
static NSString *const kParameterColumnIdentifier = @"kParameterColumnIdentifier";
NSString *const kTextColorWellIdentifier = @"kTextColorWellIdentifier";
NSString *const kBackgroundColorWellIdentifier = @"kBackgroundColorWellIdentifier";
NSString *const kTwoPraramNameColumnIdentifier = @"kTwoPraramNameColumnIdentifier";
NSString *const kTwoPraramValueColumnIdentifier = @"kTwoPraramValueColumnIdentifier";

@interface iTermTwoStringView: NSTableCellView<iTermOptionallyBordered>
- (instancetype)initWithFirst:(NSView *)first second:(NSView *)second;
@end

@implementation iTermTwoStringView {
    NSView *_first;
    NSView *_second;
}

- (instancetype)initWithFirst:(NSView *)first second:(NSView *)second {
    self = [super init];
    if (self) {
        [self addSubview:first];
        [self addSubview:second];
        _first = first;
        _second = second;
        self.autoresizesSubviews = NO;
        [self layoutSubviews];
    }
    return self;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self layoutSubviews];
}

// For reasons I cannot scrute, resizeSubviewsWithOldSize: doesn't get called but this does.
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self layoutSubviews];
}

- (void)layoutSubviews {
    const CGFloat margin = 5;
    const CGFloat width = (NSWidth(self.bounds) - margin) / 2;
    const CGFloat height = NSHeight(self.bounds);
    _first.frame = NSMakeRect(0, 0, width, height);
    _second.frame = NSMakeRect(NSMaxX(_first.frame) + margin, 0, width, height);
}

- (void)setOptionalBorderEnabled:(BOOL)enabled {
    if ([_first conformsToProtocol:@protocol(iTermOptionallyBordered)]) {
        [(id<iTermOptionallyBordered>)_first setOptionalBorderEnabled:enabled];
    }
    if ([_second conformsToProtocol:@protocol(iTermOptionallyBordered)]) {
        [(id<iTermOptionallyBordered>)_second setOptionalBorderEnabled:enabled];
    }
}

@end


// This is a color well that continues to work after it's removed from the view
// hierarchy. NSTableView likes to randomly remove its views, so a regular
// CPKColorWell won't work properly. A popover gets angry if its presenting
// view is not in the view hierarchy while it's opening, and unfortunately
// merely opening a popover triggers the table view to reload some of its views
// (at least sometimes, on OS 10.10).
@interface iTermColorWell : CPKColorWell
@end

@implementation iTermColorWell

- (NSRect)presentationRect {
    NSScrollView *scrollView = [self enclosingScrollView];
    return [scrollView convertRect:self.bounds fromView:self];
}

- (NSView *)presentingView {
    return [self enclosingScrollView];
}

@end

@interface TriggerController() <iTermTriggerParameterController, iTermTriggerDelegate>
// Keeps the color well whose popover is currently open from getting
// deallocated. It may get removed from the view hierarchy but we need it to
// continue existing so we can get the color out of it.
@property(nonatomic, strong) iTermColorWell *activeWell;
@end

@implementation TriggerController {
    NSArray *_triggers;
    // Gives the index of the row being edited while a textfield cell is editing.
    NSInteger _textEditingRow;
    id _parameterDelegate;

    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_regexColumn;
    IBOutlet NSTableColumn *_partialLineColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSTableColumn *_parametersColumn;
    IBOutlet NSTableColumn *_enabledColumn;
    IBOutlet NSButton *_removeTriggerButton;
    IBOutlet NSButton *_interpolatedStringParameters;
    IBOutlet NSButton *_updateProfileButton;
    NSArray *_cached;
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"iTermTriggersPanel"];
    if (self) {
        NSMutableArray *triggers = [NSMutableArray array];
        for (Class class in [self.class triggerClasses]) {
            [triggers addObject:[[class alloc] init]];
        }
        for (Trigger *trigger in triggers) {
            trigger.delegate = self;
        }
        _triggers = triggers;
        _textEditingRow = -1;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAllProfiles:)
                                                     name:kReloadAllProfiles
                                                   object:nil];
    }
    return self;
}

+ (NSArray<Class> *)triggerClasses {
    NSArray *allClasses = @[ [AlertTrigger class],
                             [AnnotateTrigger class],
                             [BellTrigger class],
                             [BounceTrigger class],
                             [iTermRPCTrigger class],
                             [CaptureTrigger class],
                             [iTermInjectTrigger class],
                             [iTermHighlightLineTrigger class],
                             [iTermUserNotificationTrigger class],
                             [iTermSetUserVariableTrigger class],
                             [iTermShellPromptTrigger class],
                             [iTermSetTitleTrigger class],
                             [SendTextTrigger class],
                             [ScriptTrigger class],
                             [CoprocessTrigger class],
                             [MuteCoprocessTrigger class],
                             [HighlightTrigger class],
                             [MarkTrigger class],
                             [PasswordTrigger class],
                             [iTermHyperlinkTrigger class],
                             [SetDirectoryTrigger class],
                             [SetHostnameTrigger class],
                             [StopTrigger class] ];

    return [allClasses sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                  return [[obj1 title] compare:[obj2 title]];
              }];
}

- (void)awakeFromNib {
    [_tableView registerForDraggedTypes:@[ kiTermTriggerControllerPasteboardType ]];
    _tableView.doubleAction = @selector(doubleClick:);
    _tableView.target = self;
    [self updateCopyToProfileButtonVisibility];
    [self updateUseInterpolatedStringParametersState];
}

- (void)setDelegate:(id<TriggerDelegate>)delegate {
    _delegate = delegate;
    [self updateCopyToProfileButtonVisibility];
}

- (BOOL)sharedProfileTriggersDifferFromMine {
    if ([[ProfileModel sharedInstance] bookmarkWithGuid:self.guid] != nil) {
        return NO;
    }
    NSString *originalGUID = self.bookmark[KEY_ORIGINAL_GUID];
    if (!originalGUID) {
        return NO;
    }
    Profile *sharedProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:originalGUID];
    if (!sharedProfile) {
        return NO;
    }
    NSArray *sharedTriggers = sharedProfile[KEY_TRIGGERS];
    NSArray *myTriggers = [self triggerDictionariesForCurrentProfile];
    if (![sharedTriggers isEqual:myTriggers]) {
        return YES;
    }

    if ([iTermProfilePreferences boolForKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS inProfile:sharedProfile] !=
        [iTermProfilePreferences boolForKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS inProfile:self.bookmark]) {
        return YES;
    }
    return NO;
}

- (void)updateCopyToProfileButtonVisibility {
    if (self.delegate) {
        _updateProfileButton.hidden = ![self.delegate respondsToSelector:@selector(triggersCopyToProfile)];
        _updateProfileButton.enabled = [self sharedProfileTriggersDifferFromMine];
    }
}

- (void)windowWillOpen {
    for (Trigger *trigger in _triggers) {
        [trigger reloadData];
    }
}

- (int)numberOfTriggers {
    return [[self.class triggerClasses] count];
}

- (int)indexOfAction:(NSString *)action {
    int n = [self numberOfTriggers];
    NSArray *classes = [self.class triggerClasses];
    for (int i = 0; i < n; i++) {
        NSString *className = NSStringFromClass(classes[i]);
        if ([className isEqualToString:action]) {
            return i;
        }
        Class theClass = NSClassFromString(className);
        if ([[theClass synonyms] containsObject:action]) {
            return i;
        }
    }
    return -1;
}

// Index in triggerClasses of an object of class "c"
- (NSInteger)indexOfTriggerClass:(Class)c {
    NSArray *classes = [self.class triggerClasses];
    for (int i = 0; i < classes.count; i++) {
        if (classes[i] == c) {
            return i;
        }
    }
    return -1;
}

- (Trigger *)triggerWithAction:(NSString *)action {
    int i = [self indexOfAction:action];
    if (i == -1) {
        return nil;
    }
    return _triggers[i];
}

- (Profile *)bookmark {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (NSArray *)triggerDictionariesForCurrentProfile {
    Profile *bookmark = [self bookmark];
    NSArray *triggers = [bookmark objectForKey:KEY_TRIGGERS];
    _cached = triggers ? triggers : [NSArray array];
    return _cached;
}

- (void)setTriggerDictionary:(NSDictionary *)triggerDictionary
                      forRow:(NSInteger)rowIndex
                  reloadData:(BOOL)shouldReload {
    if (shouldReload) {
        // Stop editing. A reload while editing crashes.
        [_tableView reloadData];
    }
    NSMutableArray *triggerDictionaries = [[self triggerDictionariesForCurrentProfile] mutableCopy];
    if (rowIndex < 0) {
        assert(triggerDictionary);
        [triggerDictionaries addObject:triggerDictionary];
    } else {
        if (triggerDictionary) {
            [triggerDictionaries replaceObjectAtIndex:rowIndex withObject:triggerDictionary];
        } else {
            [triggerDictionaries removeObjectAtIndex:rowIndex];
        }
    }
    [_delegate triggerChanged:self newValue:triggerDictionaries];
    if (shouldReload) {
        [_tableView reloadData];
    }
}

- (void)moveTriggerOnRow:(int)sourceRow toRow:(int)destinationRow {
    // Stop editing. A reload while editing crashes.
    [_tableView reloadData];
    NSMutableArray *triggerDictionaries = [[self triggerDictionariesForCurrentProfile] mutableCopy];
    if (destinationRow > sourceRow) {
        --destinationRow;
    }
    NSDictionary *temp = triggerDictionaries[sourceRow];
    [triggerDictionaries removeObjectAtIndex:sourceRow];
    [triggerDictionaries insertObject:temp atIndex:destinationRow];
    [_delegate triggerChanged:self newValue:triggerDictionaries];
    [_tableView reloadData];
}

- (BOOL)actionTakesParameter:(NSString *)action {
    return [[self triggerWithAction:action] takesParameter];
}

- (NSDictionary *)defaultTriggerDictionary {
    int index = [self indexOfTriggerClass:[BounceTrigger class]];
    Trigger *trigger = _triggers[index];
    return @{ kTriggerRegexKey: @"",
              kTriggerActionKey: [trigger action] };
}

- (void)setGuid:(NSString *)guid {
    _guid = [guid copy];
    [_tableView reloadData];
    [self updateUseInterpolatedStringParametersState];
}

- (void)updateUseInterpolatedStringParametersState {
    _interpolatedStringParameters.state = [iTermProfilePreferences boolForKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS inProfile:[self bookmark]] ? NSControlStateValueOn : NSControlStateValueOff;
}

+ (NSTextField *)labelWithString:(NSString *)string origin:(NSPoint)origin {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(origin.x,
                                                                           origin.y,
                                                                           0,
                                                                           0)];
    [textField setBezeled:NO];
    [textField setDrawsBackground:NO];
    [textField setEditable:NO];
    [textField setSelectable:NO];
    textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    textField.textColor = [NSColor textColor];
    textField.stringValue = string;
    [textField sizeToFit];

    return textField;
}

- (void)reloadAllProfiles:(NSNotification *)notification {
    if (_cached && ![_cached isEqual:[self triggerDictionariesForCurrentProfile]]) {
        [_tableView reloadData];
    }
    [self updateUseInterpolatedStringParametersState];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    [self updateCopyToProfileButtonVisibility];
    return [[self triggerDictionariesForCurrentProfile] count];
}

#pragma mark Drag/Drop

- (BOOL)tableView:(NSTableView *)tableView
    writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard*)pasteboard {
    NSMutableArray *indexes = [NSMutableArray array];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexes addObject:@(idx)];
    }];

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:indexes
                                         requiringSecureCoding:NO
                                                         error:nil];
    [pasteboard declareTypes:@[ kiTermTriggerControllerPasteboardType ] owner:self];
    [pasteboard setData:data forType:kiTermTriggerControllerPasteboardType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != aTableView) {
        return NSDragOperationNone;
    }

    // Add code here to validate the drop
    switch (operation) {
        case NSTableViewDropOn:
            return NSDragOperationNone;

        case NSTableViewDropAbove:
            return NSDragOperationMove;

        default:
            return NSDragOperationNone;
    }
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    NSData *rowData = [pasteboard dataForType:kiTermTriggerControllerPasteboardType];
    NSError *error = nil;
    NSArray *indexes = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSArray class]
                                                         fromData:rowData
                                                            error:&error];
    if (error) {
        DLog(@"Drop failed: %@", error);
        return NO;
    }

    // This code assumes you can only select one trigger at a time.
    int sourceRow = [indexes[0] intValue];
    [self moveTriggerOnRow:sourceRow toRow:row];

    return YES;
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
                      row:(NSInteger)rowIndex {
    if (aTableColumn == _regexColumn || aTableColumn == _partialLineColumn | aTableColumn == _enabledColumn) {
        return YES;
    }
    if (aTableColumn == _parametersColumn) {
        NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][rowIndex];
        NSString *action = triggerDictionary[kTriggerActionKey];
        return [self actionTakesParameter:action];
    }
    return NO;
}

+ (NSView *)viewForParameterForTrigger:(Trigger *)trigger
                                  size:(CGSize)size
                                 value:(id)value
                              receiver:(id<iTermTriggerParameterController>)receiver
                   interpolatedStrings:(BOOL)interpolatedStrings
                             tableView:(NSTableView *)tableView
                           delegateOut:(out id *)delegateOut
                           wellFactory:(CPKColorWell *(^ NS_NOESCAPE)(NSRect, NSColor *))wellFactory {
    if (![trigger takesParameter]) {
        return [[NSView alloc] initWithFrame:NSZeroRect];
    }
    id<iTermFocusReportingTextFieldDelegate> delegate = *delegateOut ?: receiver;

    if ([trigger paramIsTwoColorWells]) {
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                                     0,
                                                                     size.width,
                                                                     size.height)];
        CGFloat x = 4;
        NSTextField *label = [self labelWithString:@"Text:" origin:NSMakePoint(x, 0)];
        [container addSubview:label];
        x += label.frame.size.width;
        const CGFloat kWellWidth = 30;
        CPKColorWell *well = wellFactory(NSMakeRect(x,
                                                    0,
                                                    kWellWidth,
                                                    size.height),
                                         trigger.textColor);
        well.identifier = kTextColorWellIdentifier;

        [container addSubview:well];

        x += 10 + kWellWidth;
        label = [self labelWithString:@"Background:" origin:NSMakePoint(x, 0)];
        [container addSubview:label];
        x += label.frame.size.width;

        well = wellFactory(NSMakeRect(x,
                                      0,
                                      kWellWidth,
                                      size.height),
                           trigger.backgroundColor);
        [container addSubview:well];
        well.identifier = kBackgroundColorWellIdentifier;
        return container;
    }
    if ([trigger paramIsTwoStrings]) {
        const CGFloat margin = 5;
        const NSSize subsize = NSMakeSize((size.width - margin) / 2, size.height);
        iTermTuple<NSString *, NSString *> *pair = [iTermTwoParameterTriggerCodec tupleFromString:[NSString castFrom:value]];
        NSTextField *nameTextField = [self newTextFieldOfSize:subsize
                                                        value:pair.firstObject
                                                  placeholder:@"Name"
                                                   identifier:kTwoPraramNameColumnIdentifier];
        nameTextField.delegate = delegate;

        NSTextField *valueTextField = [self newTextFieldOfSize:subsize
                                                         value:pair.secondObject
                                                   placeholder:@"Value"
                                                    identifier:kTwoPraramValueColumnIdentifier];
        valueTextField.delegate = delegate;

        iTermTwoStringView *container = [[iTermTwoStringView alloc] initWithFirst:nameTextField
                                                                           second:valueTextField];
        container.frame = NSMakeRect(0, 0, size.width, size.height);
        return container;

    }
    if ([trigger paramIsPopupButton]) {
        NSPopUpButton *popUpButton = [[NSPopUpButton alloc] init];
        [popUpButton setTitle:@""];
        popUpButton.bordered = NO;

        NSMenu *theMenu = popUpButton.menu;
        BOOL isFirst = YES;
        for (NSDictionary *items in [trigger groupedMenuItemsForPopupButton]) {
            if (!isFirst) {
                [theMenu addItem:[NSMenuItem separatorItem]];
            }
            isFirst = NO;
            for (id object in [trigger objectsSortedByValueInDict:items]) {
                NSString *theTitle = [items objectForKey:object];
                if (theTitle) {
                    NSMenuItem *anItem = [[NSMenuItem alloc] initWithTitle:theTitle
                                                                    action:nil
                                                             keyEquivalent:@""];
                    [theMenu addItem:anItem];
                }
            }
        }

        id param = value;
        if (!param) {
            // Force popup buttons to have the first item selected by default
            [popUpButton selectItemAtIndex:trigger.defaultIndex];
        } else {
            [popUpButton selectItemAtIndex:[trigger indexForObject:param]];
        }
        popUpButton.target = receiver;
        popUpButton.action = @selector(parameterPopUpButtonDidChange:);

        return popUpButton;
    }

    // If not a popup button, then text by default.
    iTermFocusReportingTextField *textField = [self newTextFieldOfSize:size
                                                                 value:value
                                                           placeholder:[trigger triggerOptionalParameterPlaceholderWithInterpolation:interpolatedStrings]
                                                            identifier:kParameterColumnIdentifier];
    *delegateOut = [trigger newParameterDelegateWithPassthrough:receiver];
    textField.delegate = delegate;
    textField.identifier = kParameterColumnIdentifier;
    return textField;
}

+ (iTermFocusReportingTextField *)newTextFieldOfSize:(NSSize)size
                                               value:(NSString *)value
                                         placeholder:(NSString *)placeholder
                                          identifier:(NSString *)identifier {
    iTermFocusReportingTextField *textField =
    [[iTermFocusReportingTextField alloc] initWithFrame:NSMakeRect(0,
                                                                   0,
                                                                   size.width,
                                                                   size.height)];
    textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    textField.stringValue = value ?: @"";
    textField.editable = YES;
    textField.selectable = YES;
    textField.bordered = NO;
    textField.drawsBackground = NO;
    textField.placeholderString = placeholder;
    textField.identifier = identifier;
    textField.lineBreakMode = NSLineBreakByCharWrapping;
    
    return textField;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][row];
    if (tableColumn == _actionColumn) {
        NSPopUpButton *popUpButton = [[NSPopUpButton alloc] init];
        [popUpButton setTitle:[[_triggers[0] class] title]];
        popUpButton.bordered = NO;
        for (int i = 0; i < [self numberOfTriggers]; i++) {
            [popUpButton addItemWithTitle:[[_triggers[i] class] title]];
        }
        NSString *action = triggerDictionary[kTriggerActionKey];
        [popUpButton selectItemAtIndex:[self indexOfAction:action]];
        popUpButton.target = self;
        popUpButton.action = @selector(actionDidChange:);

        return popUpButton;
    } else if (tableColumn == _regexColumn) {
        NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][row];
        NSTextField *textField =
            [[NSTextField alloc] initWithFrame:NSMakeRect(0,
                                                          0,
                                                          tableColumn.width,
                                                          self.tableView.rowHeight)];
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        textField.stringValue = triggerDictionary[kTriggerRegexKey] ?: @"";
        textField.editable = YES;
        textField.selectable = YES;
        textField.bordered = NO;
        textField.drawsBackground = NO;
        textField.delegate = self;
        textField.identifier = kRegexColumnIdentifier;

        return textField;
    } else if (tableColumn == _partialLineColumn) {
        NSButton *checkbox = [[NSButton alloc] initWithFrame:NSZeroRect];
        [checkbox sizeToFit];
        [checkbox setButtonType:NSButtonTypeSwitch];
        checkbox.title = @"";
        checkbox.state = [triggerDictionary[kTriggerPartialLineKey] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.target = self;
        checkbox.action = @selector(instantDidChange:);
        return checkbox;
    } else if (tableColumn == _enabledColumn) {
        NSButton *checkbox = [[NSButton alloc] initWithFrame:NSZeroRect];
        [checkbox sizeToFit];
        [checkbox setButtonType:NSButtonTypeSwitch];
        checkbox.title = @"";
        checkbox.state = [triggerDictionary[kTriggerDisabledKey] boolValue] ? NSControlStateValueOff : NSControlStateValueOn;
        checkbox.target = self;
        checkbox.action = @selector(enabledDidChange:);
        return checkbox;
    } else if (tableColumn == _parametersColumn) {
        NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
        Trigger *trigger = [self triggerWithAction:triggerDicts[row][kTriggerActionKey]];
        trigger.param = triggerDicts[row][kTriggerParameterKey];
        id delegateToSave;
        NSView *result = [self.class viewForParameterForTrigger:trigger
                                                           size:NSMakeSize(tableColumn.width, _tableView.rowHeight)
                                                          value:triggerDictionary[kTriggerParameterKey]
                                                       receiver:self
                                            interpolatedStrings:_interpolatedStringParameters.state == NSControlStateValueOn
                                                      tableView:tableView
                                                    delegateOut:&delegateToSave
                                                    wellFactory:
                          ^iTermColorWell *(NSRect frame,
                                            NSColor *color) {
            iTermColorWell *well = [[iTermColorWell alloc] initWithFrame:frame colorSpace:[NSColorSpace it_defaultColorSpace]];
            well.noColorAllowed = YES;
            well.continuous = NO;
            well.tag = row;
            well.color = color;
            well.target = self;
            well.action = @selector(colorWellDidChange:);
            __weak __typeof(self) weakSelf = self;
            __weak __typeof(well) weakWell = well;
            well.willOpenPopover = ^() {
                if (weakWell) {
                    weakSelf.activeWell = weakWell;
                }
            };
            well.willClosePopover = ^() {
                if (self.activeWell == well) {
                    self.activeWell = nil;
                }
            };
            return well;
        }];
        _parameterDelegate = delegateToSave;
        return result;
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
    _removeTriggerButton.enabled = self.hasSelection;
}

#pragma mark NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    [_tableView reloadData];
    if ([[[NSColorPanel sharedColorPanel] accessoryView] isKindOfClass:[iTermNoColorAccessoryButton class]]) {
        [[NSColorPanel sharedColorPanel] setAccessoryView:nil];
        [[NSColorPanel sharedColorPanel] close];
    }
}

#pragma mark - Actions

- (IBAction)addTrigger:(id)sender {
    [self setTriggerDictionary:[self defaultTriggerDictionary] forRow:-1 reloadData:YES];
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_tableView.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeTrigger:(id)sender {
    if (_tableView.selectedRow < 0) {
        XLog(@"This shouldn't happen: you pressed the button to remove a trigger but no row is selected");
        return;
    }
    [self setTriggerDictionary:nil forRow:[_tableView selectedRow] reloadData:YES];
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
    _removeTriggerButton.enabled = self.hasSelection;
}

- (IBAction)toggleUseInterpolatedStrings:(id)sender {
    const BOOL wasEnabled = [iTermProfilePreferences boolForKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS inProfile:[self bookmark]];
    _interpolatedStringParameters.state = (!wasEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    [self.delegate triggerSetUseInterpolatedStrings:_interpolatedStringParameters.state == NSControlStateValueOn];
    [_tableView reloadData];
}

- (void)doubleClick:(id)sender {
    NSPoint screenLocation = [NSEvent mouseLocation];
    NSPoint windowLocation = [self.window convertRectFromScreen:NSMakeRect(screenLocation.x,
                                                                           screenLocation.y,
                                                                           0,
                                                                           0)].origin;
    NSPoint tableLocation = [_tableView convertPoint:windowLocation fromView:nil];
    NSInteger row = [_tableView rowAtPoint:tableLocation];
    NSInteger column = [_tableView columnAtPoint:tableLocation];
    if (row >= 0 && column >= 0) {
        NSView *view = [_tableView viewAtColumn:column row:row makeIfNecessary:NO];
        if (view && [view isKindOfClass:[NSTextField class]] && [(NSTextField *)view isEditable]) {
            [[view window] makeFirstResponder:view];
        }
    }
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.iterm2.com/triggers.html"]];
}

- (void)colorWellDidChange:(CPKColorWell *)colorWell {
    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    NSInteger row = colorWell.tag;
    if (row < 0 || row >= triggerDicts.count) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[self triggerDictionariesForCurrentProfile][row] mutableCopy];
    Trigger<iTermColorSettable> *trigger = (id)[Trigger triggerFromDict:triggerDictionary];
    if ([colorWell.identifier isEqual:kTextColorWellIdentifier]) {
        [trigger setTextColor:colorWell.color];
    } else {
        [trigger setBackgroundColor:colorWell.color];
    }
    if (trigger.param) {
        triggerDictionary[kTriggerParameterKey] = trigger.param;
    } else {
        [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    }
    // Don't reload data. If this was called because another color picker was opening, reloading the
    // table will cause the presenting view to disappear. That prevents the new popover from
    // appearing correctly.
    [self setTriggerDictionary:triggerDictionary forRow:row reloadData:NO];
}

- (void)instantDidChange:(NSButton *)checkbox {
    NSNumber *newValue = checkbox.state == NSControlStateValueOn ? @(YES) : @(NO);
    NSInteger row = [_tableView rowForView:checkbox];

    // If a text field is editing, make it save its contents before we get the trigger dictionary.
    [_tableView reloadData];

    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    if (row < 0 || row >= triggerDicts.count) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[self triggerDictionariesForCurrentProfile][row] mutableCopy];
    triggerDictionary[kTriggerPartialLineKey] = newValue;
    [self setTriggerDictionary:triggerDictionary forRow:row reloadData:YES];
}

- (void)enabledDidChange:(NSButton *)checkbox {
    NSNumber *newValue = checkbox.state == NSControlStateValueOff ? @YES : @NO;
    NSInteger row = [_tableView rowForView:checkbox];

    // If a text field is editing, make it save its contents before we get the trigger dictionary.
    [_tableView reloadData];

    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    if (row < 0 || row >= triggerDicts.count) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[self triggerDictionariesForCurrentProfile][row] mutableCopy];
    triggerDictionary[kTriggerDisabledKey] = newValue;
    [self setTriggerDictionary:triggerDictionary forRow:row reloadData:YES];
}

- (void)actionDidChange:(NSPopUpButton *)sender {
    NSInteger rowIndex = [_tableView rowForView:sender];
    if (rowIndex < 0) {
        return;
    }
    NSInteger indexOfSelectedAction = [sender indexOfSelectedItem];

    // If a text field is being edited, end it and update the trigger dictionary before we fetch it.
    [_tableView reloadData];

    NSMutableDictionary *triggerDictionary =
        [[self triggerDictionariesForCurrentProfile][rowIndex] mutableCopy];
    Trigger *theTrigger = _triggers[indexOfSelectedAction];
    triggerDictionary[kTriggerActionKey] = [theTrigger action];
    [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    Trigger *triggerObj = [self triggerWithAction:triggerDictionary[kTriggerActionKey]];
    if ([triggerObj paramIsPopupButton]) {
        triggerDictionary[kTriggerParameterKey] = [triggerObj defaultPopupParameterObject];
    } else if ([triggerObj triggerOptionalDefaultParameterValueWithInterpolation:_interpolatedStringParameters.state == NSControlStateValueOn]) {
        triggerDictionary[kTriggerParameterKey] = [triggerObj triggerOptionalDefaultParameterValueWithInterpolation:_interpolatedStringParameters.state == NSControlStateValueOn];
    }
    [self setTriggerDictionary:triggerDictionary forRow:rowIndex reloadData:YES];
}

- (void)parameterPopUpButtonDidChange:(NSPopUpButton *)sender {
    NSInteger rowIndex = [_tableView rowForView:sender];
    if (rowIndex < 0) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[self triggerDictionariesForCurrentProfile][rowIndex] mutableCopy];
    Trigger *triggerObj = [self triggerWithAction:triggerDictionary[kTriggerActionKey]];
    id parameter = [triggerObj objectAtIndex:[sender indexOfSelectedItem]];
    if (parameter) {
        triggerDictionary[kTriggerParameterKey] = parameter;
    } else {
        [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    }
    [self setTriggerDictionary:triggerDictionary forRow:rowIndex reloadData:YES];
}

- (IBAction)closeTriggersSheet:(id)sender {
    [self.delegate triggersCloseSheet];
}

- (IBAction)copyToProfile:(id)sender {
    if ([self.delegate respondsToSelector:@selector(triggersCopyToProfile)]) {
        [self.delegate triggersCopyToProfile];
        [self updateCopyToProfileButtonVisibility];
    }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidBeginEditing:(NSNotification *)obj {
    // We have to save this here because when -reloadData gets called then the text field is no longer
    // in the table and -rowForView: will return -1.
    _textEditingRow = [_tableView rowForView:obj.object];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    if (_textEditingRow >= [[self triggerDictionariesForCurrentProfile] count]) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[self triggerDictionariesForCurrentProfile][_textEditingRow] mutableCopy];
    if ([textField.identifier isEqual:kRegexColumnIdentifier]) {
        triggerDictionary[kTriggerRegexKey] = [textField stringValue];
        [self setTriggerDictionary:triggerDictionary forRow:_textEditingRow reloadData:YES];
    } else if ([textField.identifier isEqual:kParameterColumnIdentifier]) {
        triggerDictionary[kTriggerParameterKey] = [textField stringValue];
        [self setTriggerDictionary:triggerDictionary forRow:_textEditingRow reloadData:YES];
    } else if ([textField.identifier isEqual:kTwoPraramNameColumnIdentifier]) {
        iTermTuple<NSString *, NSString *> *pair = [iTermTwoParameterTriggerCodec tupleFromString:[NSString castFrom:triggerDictionary[kTriggerParameterKey]]];
        pair.firstObject = textField.stringValue;
        triggerDictionary[kTriggerParameterKey] = [iTermTwoParameterTriggerCodec stringFromTuple:pair];
        [self setTriggerDictionary:triggerDictionary forRow:_textEditingRow reloadData:YES];
    } else if ([textField.identifier isEqual:kTwoPraramValueColumnIdentifier]) {
        iTermTuple<NSString *, NSString *> *pair = [iTermTwoParameterTriggerCodec tupleFromString:[NSString castFrom:triggerDictionary[kTriggerParameterKey]]];
        pair.secondObject = textField.stringValue;
        triggerDictionary[kTriggerParameterKey] = [iTermTwoParameterTriggerCodec stringFromTuple:pair];
        [self setTriggerDictionary:triggerDictionary forRow:_textEditingRow reloadData:YES];
    }
    _textEditingRow = -1;
}

- (void)profileDidChange {
    _textEditingRow = -1;
    [_tableView reloadData];
}

#pragma mark - iTermTriggerDelegate

- (void)triggerDidChangeParameterOptions:(Trigger *)sender {
    const NSInteger columnIndex = [[_tableView tableColumns] indexOfObject:_parametersColumn];
    if (columnIndex == NSNotFound) {
        DLog(@"No param column!");
        return;
    }
    NSIndexSet *rowIndexes = [self.triggerDictionariesForCurrentProfile indexesOfObjectsPassingTest:^BOOL(NSDictionary *_Nonnull dict, NSUInteger idx, BOOL * _Nonnull stop) {
        return [NSStringFromClass([sender class]) isEqual:dict[kTriggerActionKey]];
    }];
    [_tableView reloadDataForRowIndexes:rowIndexes
                          columnIndexes:[NSIndexSet indexSetWithIndex:columnIndex]];
}

@end

