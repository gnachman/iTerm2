//
//  SmartSelection.m
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SmartSelectionController.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "ProfileModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermProfilePreferences.h"
#import "iTermTextExtractor.h"
#import "iTermUserDefaults.h"

NSString *const kRegexKey = @"regex";
NSString *const kNotesKey = @"notes";
NSString *const kNotesLocalizationKey = @"notesLocalizationKey";
NSString *const kPrecisionKey = @"precision";
NSString *const kActionsKey = @"actions";

NSString *const kVeryLowPrecision = @"very_low";
NSString *const kLowPrecision = @"low";
NSString *const kNormalPrecision = @"normal";
NSString *const kHighPrecision = @"high";
NSString *const kVeryHighPrecision = @"very_high";

static NSString *const kLogDebugInfoKey = @"Log Smart Selection Debug Info";

const double SmartSelectionVeryLowPrecision = 0.00001;
const double SmartSelectionLowPrecision = 0.001;
const double SmartSelectionNormalPrecision = 1.0;
const double SmartSelectionHighPrecision = 1000.0;
const double SmartSelectionVeryHighPrecision = 1000000.0;

@interface NSString(iTermTextDataSource)<iTermTextDataSource>
@end

@interface SmartSelectionController() <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, iTermPlaygroundTextViewDelegate, NSMenuItemValidation>
@end

// The default rules ship in SmartSelectionRules.plist with English "notes" and a
// stable "notesLocalizationKey". A note is stored verbatim in the profile and is
// user-editable, so the stored value stays English; we only localize the read-only
// DISPLAY of the known built-in notes (the table cell and the playground result). The
// editable name field shows the stored value unchanged so editing never persists a
// translated string.
//
// Rather than keeping a hand-maintained English -> localized table in sync with the
// plist, we derive an English-note -> localization-key map from the plist itself once,
// then localize a built-in note off its rule's key. A built-in note therefore
// localizes automatically as soon as its rule (with a notesLocalizationKey) exists in
// the plist and the catalog carries the key; no separate table can drift. User-authored
// notes are not in the plist and pass through untouched.
static NSString *iTermLocalizedSmartSelectionNote(NSString *note) {
    if (note == nil) {
        return note;
    }
    static NSDictionary<NSString *, NSString *> *noteToLocalizationKey;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
        for (NSDictionary *rule in [SmartSelectionController defaultRules]) {
            NSString *ruleNote = rule[kNotesKey];
            NSString *localizationKey = rule[kNotesLocalizationKey];
            if ([ruleNote isKindOfClass:[NSString class]] &&
                [localizationKey isKindOfClass:[NSString class]]) {
                map[ruleNote] = localizationKey;
            }
        }
        noteToLocalizationKey = map;
    });
    NSString *localizationKey = noteToLocalizationKey[note];
    if (localizationKey == nil) {
        // User-authored note (not a built-in): show the stored value verbatim.
        return note;
    }
    // The default value is the built-in's English note, so a missing catalog entry
    // still displays correct English. The key is dynamic here (derived from the
    // plist); the catalog entries are maintained alongside the plist keys.
    return [[NSBundle mainBundle] localizedStringForKey:localizationKey
                                                  value:note
                                                  table:nil];
}

@implementation SmartSelectionController {
    IBOutlet NSTableView *tableView_;
    IBOutlet ContextMenuActionPrefsController *contextMenuPrefsController_;
    IBOutlet NSButton *logDebugInfo_;

    IBOutlet NSTextField *_nameTextField;
    IBOutlet NSTextView *_regexTextView;
    IBOutlet iTermPlaygroundTextView *_playgroundTextView;
    IBOutlet NSView *_detailView;
    IBOutlet NSPopUpButton *_precisionButton;
    IBOutlet NSTextField *_playgroundResultLabel;
    IBOutlet NSTextField *_noRuleSelected;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_syntaxHelpButton;
    IBOutlet NSButton *_visualizationButton;
    IBOutlet NSButton *_actionsButton;
    NSUndoManager *_undoManager;
    iTermRegexVisualizationViewController *_visualizationViewController;
    NSPopover *_popover;
}

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

+ (NSArray<NSString *> *)precisionKeys {
    return @[ kVeryLowPrecision,
              kLowPrecision,
              kNormalPrecision,
              kHighPrecision,
              kVeryHighPrecision ];
}

- (void)dealloc {
    tableView_.delegate = nil;
    tableView_.dataSource = nil;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    DLog(@"%@", menuItem);
    if (menuItem.action == @selector(undo:)) {
        return [_undoManager canUndo];
    }
    if (menuItem.action == @selector(redo:)) {
        return [_undoManager canRedo];
    }
    return YES;
}

- (void)awakeFromNib {
    _undoManager = [[NSUndoManager alloc] init];

    _regexTextView.font = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    _regexTextView.automaticSpellingCorrectionEnabled = NO;
    _regexTextView.automaticDashSubstitutionEnabled = NO;
    _regexTextView.automaticQuoteSubstitutionEnabled = NO;
    _regexTextView.automaticDataDetectionEnabled = NO;
    _regexTextView.automaticLinkDetectionEnabled = NO;
    _regexTextView.smartInsertDeleteEnabled = NO;
    _regexTextView.richText = NO;

    _playgroundTextView.font = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    _playgroundTextView.it_placeholderString = NSLocalizedStringWithDefaultValue(@"SmartSelection.PlaygroundPlaceholder", nil, [NSBundle mainBundle], @"Smart Selection Playground\nEnter text here, then click to see which rule matches at that location.", @"Placeholder text for the smart selection playground text view");
    _playgroundTextView.playgroundDelegate = self;
    _playgroundTextView.automaticSpellingCorrectionEnabled = NO;
    _playgroundTextView.automaticDashSubstitutionEnabled = NO;
    _playgroundTextView.automaticQuoteSubstitutionEnabled = NO;
    _playgroundTextView.automaticDataDetectionEnabled = NO;
    _playgroundTextView.automaticLinkDetectionEnabled = NO;
    _playgroundTextView.smartInsertDeleteEnabled = NO;
    _playgroundTextView.richText = NO;

    _removeButton.enabled = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(regexDidChange:)
                                                 name:NSTextDidChangeNotification
                                               object:_regexTextView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playgroundDidChange:)
                                                 name:NSTextDidChangeNotification
                                               object:_playgroundTextView];
}

+ (NSArray *)defaultRules {
    static NSArray *rulesArray;
    if (!rulesArray) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"SmartSelectionRules"
                                                                               ofType:@"plist"];
        NSDictionary* rulesDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        if (!plistFile) {
            [iTermAppSignatureValidator warnWithReason:@"While loading the default smart selection rules"];
        }
        ITCriticalError(rulesDict != nil, @"Failed to parse SmartSelectionRules in %@: %@", plistFile, [NSString stringWithContentsOfFile:plistFile encoding:NSUTF8StringEncoding error:nil]);
        rulesArray = [rulesDict objectForKey:@"Rules"];
    }
    return rulesArray;
}

+ (NSArray *)actionsInRule:(NSDictionary *)rule {
    return [rule objectForKey:kActionsKey];
}

+ (NSString *)regexInRule:(NSDictionary *)rule {
    return [rule objectForKey:kRegexKey];
}

+ (double)precisionInRule:(NSDictionary *)rule {
    NSDictionary *precisionValues = @{ kVeryLowPrecision: @(SmartSelectionVeryLowPrecision),
                                       kLowPrecision: @(SmartSelectionLowPrecision),
                                       kNormalPrecision: @(SmartSelectionNormalPrecision),
                                       kHighPrecision: @(SmartSelectionHighPrecision),
                                       kVeryHighPrecision: @(SmartSelectionVeryHighPrecision) };

    NSString *precision = rule[kPrecisionKey];
    return [precisionValues[precision] doubleValue];
}

- (Profile *)bookmark {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (ProfileModel *)modelForBookmark:(Profile *)bookmark {
    if ([[ProfileModel sharedInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sharedInstance];
    } else if ([[ProfileModel sessionsInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sessionsInstance];
    } else {
        return nil;
    }
}

- (NSArray<NSDictionary *> *)rules {
    Profile *bookmark = [self bookmark];
    NSArray<NSDictionary *> *rules = [bookmark objectForKey:KEY_SMART_SELECTION_RULES];
    return rules ? rules : [SmartSelectionController defaultRules];
}

- (NSDictionary *)defaultRule {
    return @{ kRegexKey: @"",
              kPrecisionKey: kVeryLowPrecision };
}

- (void)setRule:(NSDictionary *)rule forRow:(NSInteger)rowIndex {
    NSMutableArray *rules = [self.rules mutableCopy];
    NSInteger actualIndex = rowIndex;
    if (rowIndex < 0) {
        assert(rule);
        [rules addObject:rule];
        actualIndex = rules.count - 1;
    } else {
        if (rule) {
            [rules replaceObjectAtIndex:rowIndex withObject:rule];
        } else {
            [rules removeObjectAtIndex:rowIndex];
        }
    }
    Profile* bookmark = [self bookmark];
    [iTermProfilePreferences setObject:rules forKey:KEY_SMART_SELECTION_RULES inProfile:bookmark model:[self modelForBookmark:bookmark] withSideEffects:NO];
    if (rowIndex < 0) {
        [tableView_ insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:actualIndex]
                          withAnimation:NSTableViewAnimationEffectNone];
    } else {
        if (rule) {
            [tableView_ reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:actualIndex]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        } else {
            [tableView_ removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:actualIndex]
                              withAnimation:NSTableViewAnimationEffectNone];
        }
    }
    [tableView_ noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:rowIndex]];
    // This must flush user defaults for setUseInterpolatedStrings to work.
    [delegate_ smartSelectionChanged:nil];
}

- (IBAction)openRegexVisualizer:(NSButton *)button {
    if (!_popover || !_popover.isShown) {
        [_popover close];
        _visualizationViewController = [[iTermRegexVisualizationViewController alloc] initWithRegex:_regexTextView.textStorage.string ?: @"" maxSize:button.window.screen.visibleFrame.size];
        NSPopover *popover = [[NSPopover alloc] init];
        popover.contentViewController = _visualizationViewController;
        popover.behavior = NSPopoverBehaviorApplicationDefined;
        [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMaxX];
        _popover = popover;

        _visualizationButton.title = NSLocalizedStringWithDefaultValue(@"SmartSelection.CloseVisualization", nil, [NSBundle mainBundle], @"Close Regular Expression Visualization", @"Button title to close the regular expression visualization popover");
    } else {
        [_popover close];
        _popover = nil;
        _visualizationButton.title = NSLocalizedStringWithDefaultValue(@"SmartSelection.OpenVisualization", nil, [NSBundle mainBundle], @"Open Regular Expression Visualization", @"Button title to open the regular expression visualization popover");
    }
}

- (IBAction)syntaxHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://unicode-org.github.io/icu/userguide/strings/regexp.html"]
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.window];
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"http://www.iterm2.com/smartselection.html"]
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.window];
}

- (IBAction)addRule:(id)sender {
    [self pushUndo];
    [self setRule:[self defaultRule] forRow:-1];
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:tableView_.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeRule:(id)sender {
    [self pushUndo];
    [tableView_.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse
                                                    usingBlock:^(NSUInteger row, BOOL * _Nonnull stop) {
        [self setRule:nil forRow:row];
    }];
}

- (IBAction)loadDefaults:(id)sender {
    [self pushUndo];
    Profile *bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:[SmartSelectionController defaultRules]
                                         forKey:KEY_SMART_SELECTION_RULES
                                     inBookmark:bookmark];
    [self reloadData];
    [delegate_ smartSelectionChanged:nil];
}

- (void)setGuid:(NSString *)guid {
    if (guid == guid_ || [guid isEqualToString:guid_]) {
        return;
    }
    guid_ = [guid copy];
    [self reloadData];
}

- (NSString *)displayNameForPrecision:(NSString *)precision {
    NSDictionary *names = @{ kVeryLowPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionVeryLow", nil, [NSBundle mainBundle], @"Very Low", @"Display name for the very low precision level"),
                             kLowPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionLow", nil, [NSBundle mainBundle], @"Low", @"Display name for the low precision level"),
                             kNormalPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionNormal", nil, [NSBundle mainBundle], @"Normal", @"Display name for the normal precision level"),
                             kHighPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionHigh", nil, [NSBundle mainBundle], @"High", @"Display name for the high precision level"),
                             kVeryHighPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionVeryHigh", nil, [NSBundle mainBundle], @"Very High", @"Display name for the very high precision level") };
    return names[precision] ?: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionUndefined", nil, [NSBundle mainBundle], @"Undefined", @"Display name for an unknown precision level");
}

- (int)indexForPrecision:(NSString *)precision {
    NSUInteger index = [[SmartSelectionController precisionKeys] indexOfObject:precision];
    if (index == NSNotFound) {
        return 0;
    } else {
        return index;
    }
}

- (NSString *)precisionKeyWithIndex:(int)i {
    return [[SmartSelectionController precisionKeys] objectAtIndex:i];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    DLog(@"Reporting number of rows: %@", @(self.rules.count));
    DLog(@"%@", [NSThread callStackSymbols]);
    return self.rules.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSArray<NSDictionary *> *rules = self.rules;
    NSDictionary *rule = rules[row];
    NSAttributedString *attributedString = [self attributedStringForRule:rule];
    return [attributedString heightForWidth:tableView.tableColumns[0].width] + 8;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    NSArray<NSDictionary *> *rules = self.rules;
    NSDictionary *rule = rules[rowIndex];
    iTermTableCellViewWithTextField *view = [tableView newTableCellViewWithTextFieldUsingIdentifier:@"Smart Selection Tableview Entry"
                                                                                   attributedString:[self attributedStringForRule:rule]];
    return view;
}

- (NSAttributedString *)attributedStringForRule:(NSDictionary *)rule {
    NSAttributedString *newline = [[NSAttributedString alloc] initWithString:@"\n" attributes:self.regularAttributes];
    NSString *regex = rule[kRegexKey];
    id regexAttributedString = regex.length > 0 ? [self attributedStringForRegex:regex] : [NSNull null];
    NSArray *lines = nil;
    NSString *name = iTermLocalizedSmartSelectionNote(rule[kNotesKey]);
    NSAttributedString *precisionAttributedString = [self precisionAttributedString:rule[kPrecisionKey]
                                                                        actionCount:[[NSArray castFrom:rule[kActionsKey]] count]];
    if ([name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
        NSAttributedString *nameAttributedString = [[NSAttributedString alloc] initWithString:name
                                                                                   attributes:self.nameAttributes];
        lines = @[nameAttributedString, regexAttributedString, precisionAttributedString];
    } else {
        lines = @[regexAttributedString, precisionAttributedString];
    }
    lines = [lines filteredArrayUsingBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[NSAttributedString class]];
    }];
    return [lines it_componentsJoinedBySeparator:newline];
}

- (NSAttributedString *)precisionAttributedString:(NSString *)precision actionCount:(NSInteger)actionCount {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    NSDictionary *boldAttributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold]
    };
    NSDictionary *phrases = @{ kVeryLowPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionVeryLowPhrase", nil, [NSBundle mainBundle], @"Very low precision", @"Describes a smart selection rule using the very low precision level"),
                               kLowPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionLowPhrase", nil, [NSBundle mainBundle], @"Low precision", @"Describes a smart selection rule using the low precision level"),
                               kNormalPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionNormalPhrase", nil, [NSBundle mainBundle], @"Normal precision", @"Describes a smart selection rule using the normal precision level"),
                               kHighPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionHighPhrase", nil, [NSBundle mainBundle], @"High precision", @"Describes a smart selection rule using the high precision level"),
                               kVeryHighPrecision: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionVeryHighPhrase", nil, [NSBundle mainBundle], @"Very high precision", @"Describes a smart selection rule using the very high precision level") };
    NSString *name = phrases[precision] ?: NSLocalizedStringWithDefaultValue(@"SmartSelection.PrecisionUndefinedPhrase", nil, [NSBundle mainBundle], @"Undefined precision", @"Describes a smart selection rule using an unknown precision level");
    if (actionCount >= 1) {
        name = [name stringByAppendingString:[NSString localizedStringWithFormat:NSLocalizedStringWithDefaultValue(@"SmartSelection.ActionCountSuffix", nil, [NSBundle mainBundle], @", %ld actions", @"Suffix appended to a smart selection rule name giving its action count; %ld is the count"), (long)actionCount]];
    }
    return [[NSAttributedString alloc] initWithString:name attributes:boldAttributes];
}

- (NSDictionary *)nameAttributes {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]
    };
    return attributes;
}

- (NSDictionary *)regularAttributes {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
    return attributes;
}

- (NSAttributedString *)attributedStringForRegex:(NSString *)regex {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightRegular]
    };
    return [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/%@/", regex]
                                           attributes:attributes];
}

- (IBAction)changePrecision:(NSPopUpButton *)sender {
    [self pushUndo];
    const NSInteger rowIndex = tableView_.selectedRow;
    const NSInteger index = sender.indexOfSelectedItem;
    NSMutableDictionary *rule = [self.rules[rowIndex] mutableCopy];
    rule[kPrecisionKey] = [self precisionKeyWithIndex:index];
    [self setRule:rule forRow:rowIndex];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateDetailView];
}

- (void)reloadData {
    [tableView_ reloadData];
    [self updateDetailView];
}

- (void)updateDetailView {
    self.hasSelection = [tableView_ numberOfSelectedRows] == 1;
    _removeButton.enabled = tableView_.numberOfSelectedRows > 0;
    _detailView.hidden = !self.hasSelection;
    _noRuleSelected.hidden = self.hasSelection;
    if (tableView_.numberOfSelectedRows > 1) {
        // Localization unneeded: distinct states, not a count plural.
        _noRuleSelected.stringValue = NSLocalizedStringWithDefaultValue(@"SmartSelection.MultipleRulesSelected", nil, [NSBundle mainBundle], @"Multiple rules selected", @"Shown in the smart selection editor when more than one rule is selected");
    } else {
        _noRuleSelected.stringValue = NSLocalizedStringWithDefaultValue(@"SmartSelection.NoRuleSelected", nil, [NSBundle mainBundle], @"No rule selected", @"Shown in the smart selection editor when no rule is selected");
    }
    if (self.hasSelection) {
        const NSInteger row = [tableView_ selectedRow];
        NSDictionary *rule = self.rules[row];
        _nameTextField.stringValue = rule[kNotesKey] ?: @"";
        [_regexTextView setString:rule[kRegexKey] ?: @""];
        [_precisionButton selectItemAtIndex:[self indexForPrecision:rule[kPrecisionKey]]];
        [self updateVisualization];
        const NSInteger actionCount = [[NSArray castFrom:rule[kActionsKey]] count];
        if (actionCount == 0) {
            _actionsButton.title = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SmartSelection.Actions", nil, [NSBundle mainBundle], @"Actions…", @"Button title for the actions menu when a rule has no actions")];
        } else {
            _actionsButton.title = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SmartSelection.ActionsWithCount", nil, [NSBundle mainBundle], @"Actions (%@)…", @"Button title showing the number of actions attached to a rule; %@ is the count"), @(actionCount)];
        }
    } else {
        _nameTextField.stringValue = @"";
        [_regexTextView setString:@""];
        [_precisionButton selectItemAtIndex:0];
        [_popover close];
        _popover = nil;
    }
}

- (IBAction)logDebugInfoChanged:(id)sender {
    [[iTermUserDefaults userDefaults] setObject:[NSNumber numberWithInt:logDebugInfo_.state]
                                              forKey:kLogDebugInfoKey];
}

+ (BOOL)logDebugInfo {
    NSNumber *n = [[iTermUserDefaults userDefaults] valueForKey:kLogDebugInfoKey];
    if (n) {
        return [n intValue] == NSControlStateValueOn;
    } else {
        return NO;
    }
}

- (IBAction)editActions:(id)sender {
    if (!self.hasSelection) {
        return;
    }
    const NSInteger row = [tableView_ selectedRow];
    if (row < 0 || row >= self.rules.count) {
        return;
    }
    NSDictionary *rule = [self.rules objectAtIndex:row];
    if (!rule) {
        return;
    }
    [self pushUndo];
    NSArray *actions = [SmartSelectionController actionsInRule:rule];
    [contextMenuPrefsController_ setActions:actions browser:[[self bookmark] profileIsBrowser]];
    contextMenuPrefsController_.useInterpolatedStrings = [self useInterpolatedStrings];
    [contextMenuPrefsController_ window];
    [contextMenuPrefsController_ setDelegate:self];
    __weak __typeof(self) weakSelf = self;
    [self.window beginSheet:contextMenuPrefsController_.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->contextMenuPrefsController_.window close];
            [strongSelf updateDetailView];
        }
    }];
}

- (void)windowWillOpen {
    [logDebugInfo_ setState:[SmartSelectionController logDebugInfo] ? NSControlStateValueOn : NSControlStateValueOff];
}

#pragma mark - Context Menu Actions Delegate

- (void)contextMenuActionsChanged:(NSArray *)newActions useInterpolatedStrings:(BOOL)useInterpolatedStrings {
    if (self.hasSelection) {
        int rowIndex = [tableView_ selectedRow];
        NSMutableDictionary *rule = [[self.rules objectAtIndex:rowIndex] mutableCopy];
        [rule setObject:newActions forKey:kActionsKey];
        [self setUseInterpolatedStrings:useInterpolatedStrings];
        // This call flushes user defaults, which setUseInterpolatedStrings: needs.
        [self setRule:rule forRow:rowIndex];
    }
    [contextMenuPrefsController_.window.sheetParent endSheet:contextMenuPrefsController_.window];
}

- (void)setUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    // Note: this assumes the caller will flush to user defaults.
    Profile *profile = [self bookmark];
    [[self modelForBookmark:profile] setObject:@(useInterpolatedStrings)
                                        forKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                    inBookmark:profile];
}

- (BOOL)useInterpolatedStrings {
    return [iTermProfilePreferences boolForKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                     inProfile:self.bookmark];
}

#pragma mark - NSTextFieldDelegate

- (void)save {
    if (!self.hasSelection) {
        return;
    }
    const NSInteger rowIndex = tableView_.selectedRow;
    if (rowIndex < 0) {
        return;
    }
    [self pushUndo];
    NSMutableDictionary *rule = [self.rules[rowIndex] mutableCopy];
    rule[kNotesKey] = [_nameTextField.stringValue copy];
    rule[kRegexKey] = [_regexTextView.textStorage.string copy] ?: @"";
    rule[kPrecisionKey] = [self precisionKeyWithIndex:_precisionButton.selectedTag];
    [self setRule:rule forRow:rowIndex];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self save];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [self save];
}

- (void)regexDidChange:(NSNotification *)notification {
    [self updateVisualization];
    [self save];
}

- (void)updateVisualization {
    _visualizationViewController.regex = _regexTextView.textStorage.string ?: @"";
}

- (void)playgroundDidChange:(NSNotification *)notification {
    [self updatePlayground];
}

- (void)updatePlayground {
    if (_playgroundTextView.lastCoord.x < 0 || _playgroundTextView.lastCoord.y < 0) {
        _playgroundResultLabel.stringValue = NSLocalizedStringWithDefaultValue(@"SmartSelection.ClickToTest", nil, [NSBundle mainBundle], @"Click on text in playground to test rules", @"Playground prompt telling the user to click on text to test smart selection rules");
        return;
    }
    if (_playgroundTextView.lastCoord.y >= _playgroundTextView.textStorage.string.numberOfLines ||
        _playgroundTextView.lastCoord.x >= _playgroundTextView.textStorage.string.width) {
        _playgroundResultLabel.stringValue = NSLocalizedStringWithDefaultValue(@"SmartSelection.ClickToTest", nil, [NSBundle mainBundle], @"Click on text in playground to test rules", @"Playground prompt telling the user to click on text to test smart selection rules");
        return;
    }
    iTermTextExtractor *extractor = [[iTermTextExtractor alloc] initWithDataSource:_playgroundTextView.textStorage.string ?: @""];
    VT100GridWindowedRange relativeRange;
    SmartMatch *result = [extractor smartSelectionAt:_playgroundTextView.lastCoord
                                           withRules:self.rules
                                      actionRequired:NO
                                               range:&relativeRange
                                    ignoringNewlines:NO];
    if (!result) {
        _playgroundResultLabel.stringValue = NSLocalizedStringWithDefaultValue(@"SmartSelection.NoMatch", nil, [NSBundle mainBundle], @"No match", @"Playground result label shown when no smart selection rule matches");
        return;
    }
    _playgroundResultLabel.stringValue = iTermLocalizedSmartSelectionNote(result.rule[kNotesKey]);
    [_playgroundTextView highlightGridRange:VT100GridCoordRangeMake(result.startX,
                                                                    result.absStartY,
                                                                    result.endX,
                                                                    result.absEndY)];
}

- (IBAction)undo:(id)sender {
    [_undoManager undo];
}

- (IBAction)redo:(id)sender {
    [_undoManager redo];
}

- (void)pushUndo {
    [_undoManager registerUndoWithTarget:self
                                selector:@selector(setRules:)
                                  object:self.rules];
}

- (void)setRules:(NSArray<NSDictionary *> *)rules {
    Profile *profile = [self bookmark];
    [[self modelForBookmark:profile] setObject:rules forKey:KEY_SMART_SELECTION_RULES
                                    inBookmark:profile];
    [self reloadData];
    [delegate_ smartSelectionChanged:nil];
}

#pragma mark - iTermPlaygroundTextViewDelegate

- (void)playgroundClickCoordinateDidChange:(iTermPlaygroundTextView *)sender coordinate:(VT100GridCoord)coordinate {
    [self updatePlayground];
}

@end

@implementation NSString(iTermTextDataSource)
- (id<VT100ScreenMarkReading> _Nullable)commandMarkAt:(VT100GridCoord)coord mustHaveCommand:(BOOL)mustHaveCommand range:(out nullable VT100GridWindowedRange *)range { 
    return nil;
}

- (NSDate * _Nullable)dateForLine:(int)line {
    return nil;
}

- (id<iTermExternalAttributeIndexReading> _Nullable)externalAttributeIndexForLine:(int)y { 
    return nil;
}

- (id)fetchLine:(int)line block:(id  _Nullable (^NS_NOESCAPE)(ScreenCharArray * _Nonnull))block {
    ScreenCharArray *sca = [self screenCharArrayForLine:line];
    return block(sca);
}

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber { 
    return iTermImmutableMetadataDefault();
}

- (nonnull ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index {
    return [self screenCharArrayForLine:index];
}

- (nonnull ScreenCharArray *)screenCharArrayForLine:(int)line {
    NSArray<NSString *> *lines = [self componentsSeparatedByString:@"\n"];
    return [[lines[line] asScreenCharArray] paddedToAtLeastLength:self.width];
}

- (long long)totalScrollbackOverflow { 
    return 0;
}

- (int)width { 
    NSArray<NSString *> *lines = [self componentsSeparatedByString:@"\n"];
    NSString *line = [lines maxWithBlock:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        return [@(obj1.length) compare:@(obj2.length)];
    }];
    const NSUInteger length = [[line asScreenCharArray] length];
    return MAX(2, length + 1);
}

- (BOOL)isFirstLineOfBlock:(int)lineNumber { 
    return NO;
}


- (int)numberOfLines { 
    return [[self componentsSeparatedByString:@"\n"] count];
}


@end
