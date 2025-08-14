//
//  SmartSelection.m
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SmartSelectionController.h"

#import "DebugLogging.h"
#import "ProfileModel.h"
#import "ITAddressBookMgr.h"
#import "FutureMethods.h"
#import "iTermTextExtractor.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermProfilePreferences.h"

NSString *const kRegexKey = @"regex";
NSString *const kNotesKey = @"notes";
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
    _playgroundTextView.it_placeholderString = @"Smart Selection Playground\nEnter text here, then click to see which rule matches at that location.";
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
        ITCriticalError(rulesDict != nil, @"Failed to parse SmartSelectionRules: %@", [NSString stringWithContentsOfFile:plistFile encoding:NSUTF8StringEncoding error:nil]);
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
    [[self modelForBookmark:bookmark] setObject:rules forKey:KEY_SMART_SELECTION_RULES inBookmark:bookmark];
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

        _visualizationButton.title = @"Close Regular Expression Visualization";
    } else {
        [_popover close];
        _popover = nil;
        _visualizationButton.title = @"Open Regular Expression Visualization";
    }
}

- (IBAction)syntaxHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://unicode-org.github.io/icu/userguide/strings/regexp.html"]];
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"http://www.iterm2.com/smartselection.html"]];
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
    guid_ = [guid copy];
    [self reloadData];
}

- (NSString *)displayNameForPrecision:(NSString *)precision {
    NSDictionary *names = @{ kVeryLowPrecision: @"Very Low",
                             kLowPrecision: @"Low",
                             kNormalPrecision: @"Normal",
                             kHighPrecision: @"High",
                             kVeryHighPrecision: @"Very High" };
    return names[precision] ?: @"Undefined";
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
    NSString *name = rule[kNotesKey];
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
    NSString *name = [[self displayNameForPrecision:precision] stringByAppendingString:@" precision"];
    if (actionCount == 1) {
        name = [name stringByAppendingFormat:@", one action"];
    } else if (actionCount > 1) {
        name = [name stringByAppendingFormat:@", %@ actions", @(actionCount)];
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
        _noRuleSelected.stringValue = @"Multiple rules selected";
    } else {
        _noRuleSelected.stringValue = @"No rule selected";
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
            _actionsButton.title = [NSString stringWithFormat:@"Actions…"];
        } else {
            _actionsButton.title = [NSString stringWithFormat:@"Actions (%@)…", @(actionCount)];
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
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:logDebugInfo_.state]
                                              forKey:kLogDebugInfoKey];
}

+ (BOOL)logDebugInfo {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] valueForKey:kLogDebugInfoKey];
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
    rule[kNotesKey] = _nameTextField.stringValue;
    rule[kRegexKey] = _regexTextView.textStorage.string ?: @"";
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
        _playgroundResultLabel.stringValue = @"Click on text in playground to test rules";
        return;
    }
    if (_playgroundTextView.lastCoord.y >= _playgroundTextView.textStorage.string.numberOfLines ||
        _playgroundTextView.lastCoord.x >= _playgroundTextView.textStorage.string.width) {
        _playgroundResultLabel.stringValue = @"Click on text in playground to test rules";
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
        _playgroundResultLabel.stringValue = @"No match";
        return;
    }
    _playgroundResultLabel.stringValue = result.rule[kNotesKey];
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
    return MAX(2, length);
}

@end
