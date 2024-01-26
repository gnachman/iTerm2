//
//  iTermSnippetsEditingViewController.m
//  iTerm2
//
//  Created by George Nachman on 9/7/20.
//

#import "iTermSnippetsEditingViewController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermCompetentTableRowView.h"
#import "iTermEditSnippetWindowController.h"
#import "iTermPreferencesBaseViewController.h"
#import "iTermSnippetsModel.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

static NSString *const iTermSnippetsEditingPasteboardType = @"com.googlecode.iterm2.iTermSnippetsEditingPasteboardType";

@interface iTermSnippetsEditingView: NSView
@end

@implementation iTermSnippetsEditingView
@end

@interface iTermSnippetsEditingViewController ()<NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@end

@implementation iTermSnippetsEditingViewController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_titleColumn;
    IBOutlet NSTableColumn *_valueColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_exportButton;
    IBOutlet NSButton *_importButton;
    IBOutlet NSSearchField *_searchField;

    NSArray<iTermSnippet *> *_allSnippets;
    NSArray<iTermSnippet *> *_filteredSnippets;
    iTermEditSnippetWindowController *_windowController;
}

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView {
    [containerView addSubview:self.view];
    containerView.autoresizesSubviews = YES;
    self.view.frame = containerView.bounds;
    [self load];
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    [self updateEnabled];
    [_tableView registerForDraggedTypes:@[ iTermSnippetsEditingPasteboardType ]];
    [_tableView reloadData];
    __weak __typeof(self) weakSelf = self;
    [iTermSnippetsDidChangeNotification subscribe:self
                                            block:^(iTermSnippetsDidChangeNotification * _Nonnull notification) {
        [weakSelf snippetsDidChange:notification];
    }];
    [container addViewToSearchIndex:_tableView
                        displayName:@"Snippets"
                            phrases:@[ @"Snippets" ]
                                key:kPreferenceKeySnippets];
}

#pragma mark - Private

- (void)load {
    _allSnippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
    _filteredSnippets = [_allSnippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [self snippetMatchesQuery:snippet];
    }];
}

- (iTermTuple<NSString *, NSSet<NSString *> *> *)phraseAndTagsFromQuery {
    NSString *query = self.query;
    if (query.length == 0) {
        return [iTermTuple tupleWithObject:@"" andObject:nil];
    }
    NSMutableSet<NSString *> *tags = [NSMutableSet set];
    NSRange tagRange = [query rangeOfString:@"tag:"];
    while (tagRange.location != NSNotFound) {
        if (tagRange.location == 0 || [query characterAtIndex:tagRange.location - 1] == ' ') {
            NSString *tag = [[[query substringFromIndex:tagRange.location + @"tag:".length] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] firstObject];
            if (tag.length) {
                NSString *before = [[query substringToIndex:tagRange.location] stringByTrimmingTrailingWhitespace];
                NSString *after = [[query substringFromIndex:NSMaxRange(tagRange) + tag.length] stringByTrimmingLeadingWhitespace];
                query = [before stringByAppendingString:after];
            }
            [tags addObject:tag];
            tagRange = [query rangeOfString:@"tag:"];
        } else {
            break;
        }
    }
    return [iTermTuple tupleWithObject:query andObject:tags];
}

- (BOOL)snippetMatchesQuery:(iTermSnippet *)snippet {
    iTermTuple<NSString *, NSSet<NSString *> *> *phraseTags = [self phraseAndTagsFromQuery];
    NSString *query = phraseTags.firstObject;
    NSSet<NSString *> *tags = phraseTags.secondObject;
    if (tags.count && ![tags isSubsetOfSet:[NSSet setWithArray:snippet.tags]]) {
        return NO;
    }
    if (query.length == 0) {
        return YES;
    }
    return ([snippet.tags containsObject:query] ||
            [snippet.title localizedCaseInsensitiveContainsString:query] ||
            [snippet.value localizedCaseInsensitiveContainsString:query]);
}

- (NSInteger)filteredIndex:(NSInteger)unfilteredIndex {
    if (unfilteredIndex >= _allSnippets.count) {
        return _filteredSnippets.count;
    }
    iTermSnippet *snippet = _allSnippets[unfilteredIndex];
    return [_filteredSnippets indexOfObject:snippet];
}

- (NSIndexSet *)filteredIndexSet:(NSIndexSet *)unfilteredIndexSet {
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    [unfilteredIndexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        const NSInteger i = [self filteredIndex:idx];
        if (i != NSNotFound) {
            [result addIndex:i];
        }
    }];
    return result;
}

- (NSInteger)insertionFilteredIndex:(NSInteger)unfilteredIndex {
    for (NSInteger i = unfilteredIndex; i < _allSnippets.count; i++) {
        NSInteger candidate = [self filteredIndex:i];
        if (candidate != NSNotFound) {
            return candidate;
        }
    }
    return _filteredSnippets.count;
}

- (NSString *)query {
    return [_searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSArray<iTermSnippet *> *)selectedSnippets {
    return [[_tableView.selectedRowIndexes it_array] mapWithBlock:^id(NSNumber *indexNumber) {
        return _filteredSnippets[indexNumber.integerValue];
    }];
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] setSnippets:snippets];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setSnippets:)
                                        object:_allSnippets];
}

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notif {
    [_tableView it_performUpdateBlock:^{
        switch (notif.mutationType) {
            case iTermSnippetsDidChangeMutationTypeEdit: {
                const NSInteger i = [self filteredIndex:notif.index];
                if (i != NSNotFound) {
                    // Row is currently visible.
                    if ([self snippetMatchesQuery:[[iTermSnippetsModel sharedInstance] snippets][notif.index]]) {
                        // Row will remain visible so just reload it.
                        [self->_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:i]
                                                    columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
                    } else {
                        // Row will cease to be visible.
                        [self->_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                                withAnimation:YES];
                    }
                } else if ([self snippetMatchesQuery:[[iTermSnippetsModel sharedInstance] snippets][notif.index]]) {
                    // Row is not currently visible but will become visible.
                    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:[self insertionFilteredIndex:notif.index]];
                    [self->_tableView insertRowsAtIndexes:indexSet
                                            withAnimation:YES];
                }
                break;
            }
            case iTermSnippetsDidChangeMutationTypeDeletion: {
                NSIndexSet *indexSet = [self filteredIndexSet:notif.indexSet];
                if (indexSet.count) {
                    [_tableView removeRowsAtIndexes:indexSet
                                      withAnimation:YES];
                }
                break;
            }
            case iTermSnippetsDidChangeMutationTypeInsertion: {
                iTermSnippet *snippet = [[iTermSnippetsModel sharedInstance] snippets][notif.index];
                if ([self snippetMatchesQuery:snippet]) {
                    const NSInteger i = [self insertionFilteredIndex:notif.index];
                    [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:i]
                                      withAnimation:YES];
                }
                break;
            }
            case iTermSnippetsDidChangeMutationTypeMove: {
                NSIndexSet *indexSet = [self filteredIndexSet:notif.indexSet];
                [_tableView removeRowsAtIndexes:indexSet
                                  withAnimation:YES];
                NSMutableIndexSet *insertionIndexes = [NSMutableIndexSet indexSet];
                const NSInteger unshiftedInsertionIndex = [self insertionFilteredIndex:notif.index];
                const NSInteger shift = [indexSet countOfIndexesInRange:NSMakeRange(0, unshiftedInsertionIndex)];
                const NSInteger insertionIndex = unshiftedInsertionIndex - shift;
                for (NSInteger i = 0; i < indexSet.count; i++) {
                    [insertionIndexes addIndex:insertionIndex + i];
                }
                [_tableView insertRowsAtIndexes:insertionIndexes
                                  withAnimation:YES];
                break;
            }
            case iTermSnippetsDidChangeMutationTypeFullReplacement:
                [_tableView reloadData];
                break;
        }
        [self load];
    }];
}

- (void)updateEnabled {
    const NSInteger numberOfRows = [[self selectedSnippets] count];
    _removeButton.enabled = numberOfRows > 0;
    _editButton.enabled = numberOfRows == 1;
    if (@available(macOS 10.16, *)) {
        _exportButton.enabled = numberOfRows > 0;
    } else {
        // This is just because we don't have SF Symbols and I don't have a nice asset to use here.
        _importButton.hidden = YES;
        _exportButton.hidden = YES;
    }
}

#pragma mark - Actions

- (void)doubleClickOnTableView:(id)sender {
    NSInteger row = [_tableView clickedRow];
    if (row < 0) {
        return;
    }
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self edit:nil];
}

- (IBAction)add:(id)sender {
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:nil
                                                                       completion:^(iTermSnippet * _Nullable snippet) {
        if (!snippet) {
            return;
        }
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    }];
    [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (IBAction)remove:(id)sender {
    NSArray<iTermSnippet *> *snippets = [self selectedSnippets];
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] removeSnippets:snippets];
}

- (IBAction)edit:(id)sender {
    iTermSnippet *snippet = [[self selectedSnippets] firstObject];
    if (snippet) {
        _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:snippet
                                                                           completion:^(iTermSnippet * _Nullable updatedSnippet) {
            if (!updatedSnippet) {
                return;
            }
            [[iTermSnippetsModel sharedInstance] replaceSnippet:snippet withSnippet:updatedSnippet];
        }];
        [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
    }
}

- (IBAction)import:(id)sender {
    NSOpenPanel *panel = [[NSOpenPanel alloc] init];
    panel.allowedFileTypes = @[ @"it2snippets" ];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    const NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) {
        return;
    }
    for (NSURL *url in panel.URLs) {
        [self importURL:url];
    }
}

- (IBAction)export:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ @"it2snippets" ];

    const NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) {
        return;
    }
    [self exportToURL:panel.URL];
}

#pragma mark - Import

- (void)importURL:(NSURL *)url {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:url.path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!content || error) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"While loading %@: %@", url.path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncImportSnippetsFailed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:[NSString stringWithFormat:@"Import Failed"]
                                    window:self.view.window];
        return;
    }

    id root = [NSJSONSerialization it_objectForJsonString:content error:&error];
    if (!root) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"While parsing %@: %@", url.path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncImportSnippetsFailed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:[NSString stringWithFormat:@"Import Failed"]
                                    window:self.view.window];
        return;
    }

    NSArray *array = [NSArray castFrom:root];
    if (!array) {
        [self showEncodingErrorForURL:url];
        return;
    }

    [self pushUndo];
    for (id element in array) {
        NSDictionary *dict = [NSDictionary castFrom:element];
        if (!dict) {
            [self showEncodingErrorForURL:url];
            return;
        }
        iTermSnippet *snippet = [[iTermSnippet alloc] initWithDictionary:dict];
        if (!snippet) {
            [self showEncodingErrorForURL:url];
            return;
        }
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    }
}

- (void)showEncodingErrorForURL:(NSURL *)url {
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Malformed file at %@", url.path]
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncSnippetEncodingError"
                           silenceable:kiTermWarningTypePersistent
                               heading:[NSString stringWithFormat:@"Import Failed"]
                                window:self.view.window];
}

#pragma mark - Export

- (void)exportToURL:(NSURL *)url {
    NSIndexSet *indexes = [_tableView selectedRowIndexes];
    NSMutableArray<NSDictionary *> *array = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        iTermSnippet *snippet = _filteredSnippets[i];
        [array addObject:snippet.dictionaryValue];
    }];
    NSString *json = [NSJSONSerialization it_jsonStringForObject:array];
    NSError *error = nil;
    [json writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Error saving to %@: %@", url.path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncSnippetWritingError"
                               silenceable:kiTermWarningTypePersistent
                                   heading:[NSString stringWithFormat:@"Export Failed"]
                                    window:self.view.window];
    }
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateEnabled];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _filteredSnippets.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == _titleColumn) {
        return [self viewForTitleColumnOnRow:row];
    }
    return [self viewForValueColumnOnRow:row];
}

- (NSView *)viewForTitleColumnOnRow:(NSInteger)row {
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];

    static NSString *const identifier = @"PrefsSnippetsTitle";
    iTermTableCellView *cellView = [_tableView makeViewWithIdentifier:identifier owner:self];
    NSTextField *textField;
    if (cellView == nil) {
        cellView = [[iTermTableCellView alloc] init];
        textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        cellView.strongTextField = textField;
        textField.font = font;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cellView addSubview:textField];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor],
            [textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor],
            [textField.topAnchor constraintEqualToAnchor:cellView.topAnchor],
            [textField.bottomAnchor constraintEqualToAnchor:cellView.bottomAnchor],
        ]];
    } else {
        textField = cellView.textField;
    }

    NSString *trimmedTitle = [_filteredSnippets[row] trimmedTitle:256];
    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: NSColor.textColor };
    NSAttributedString *titleAttributedString =
    [NSAttributedString attributedStringWithString:[@" " stringByAppendingString:trimmedTitle]
                                        attributes:attributes];
    titleAttributedString = [self attributedString:titleAttributedString byHighlightingSubstring:self.query];

    if (_filteredSnippets[row].tags.count) {
        NSArray<NSAttributedString *> *substrings = [_filteredSnippets[row].tags flatMapWithBlock:^id _Nullable(NSString * _Nonnull tag) {
            NSDictionary *attributes = @{
                NSForegroundColorAttributeName: NSColor.whiteColor,
                NSBackgroundColorAttributeName: [NSColor colorWithSRGBRed:0.97 green:0.47 blue:0.10 alpha:1.0],
                NSFontAttributeName: font
            };
            NSAttributedString *tagString = [NSAttributedString attributedStringWithString:[NSString stringWithFormat:@" %@ ", tag]
                                                                                attributes:attributes];
            NSAttributedString *space = [NSAttributedString attributedStringWithString:@" "
                                                                            attributes:@{ NSFontAttributeName: font }];
            return @[tagString, space];
        }];
        substrings = [substrings arrayByAddingObject:titleAttributedString];
        textField.attributedStringValue = [NSAttributedString attributedStringWithAttributedStrings:substrings];
    } else {
        textField.attributedStringValue = titleAttributedString;
    }
    return cellView;
}

- (NSAttributedString *)attributedString:(NSAttributedString *)document byHighlightingSubstring:(NSString *)query {
    const NSRange range = [document.string rangeOfString:query
                                                 options:NSCaseInsensitiveSearch
                                                   range:NSMakeRange(0, document.string.length)];
    if (range.location == NSNotFound) {
        return document;
    }

    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSMutableAttributedString *result = [document mutableCopy];
    [result enumerateAttributesInRange:range options:0 usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
        NSMutableDictionary *modifiedAttrs = [attrs mutableCopy];
        modifiedAttrs[NSBackgroundColorAttributeName] = [NSColor yellowColor];
        modifiedAttrs[NSForegroundColorAttributeName] = [NSColor blackColor];
        NSFont *font = attrs[NSFontAttributeName];
        if (font) {
            NSFont *boldFont = [fontManager convertFont:font toHaveTrait:NSBoldFontMask];
            if (boldFont) {
                modifiedAttrs[NSFontAttributeName] = boldFont;
            }
        }
        [result setAttributes:modifiedAttrs range:range];
    }];
    return result;
}

- (NSView *)viewForValueColumnOnRow:(NSInteger)row {
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];

    static NSString *const identifier = @"PrefsSnippetsValue";
    iTermTableCellView *cellView = [_tableView makeViewWithIdentifier:identifier owner:self];
    NSTextField *textField;
    if (cellView == nil) {
        cellView = [[iTermTableCellView alloc] init];
        textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        cellView.strongTextField = textField;
        textField.font = font;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cellView addSubview:textField];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor],
            [textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor],
            [textField.topAnchor constraintEqualToAnchor:cellView.topAnchor],
            [textField.bottomAnchor constraintEqualToAnchor:cellView.bottomAnchor],
        ]];
    } else {
        textField = cellView.textField;
    }
    NSString *string;
    if (self.query.length > 0) {
        const NSRange range = [_filteredSnippets[row].value rangeOfString:self.query
                                                                  options:NSCaseInsensitiveSearch
                                                                    range:NSMakeRange(0, _filteredSnippets[row].value.length)];
        if (range.location == NSNotFound) {
            string = [_filteredSnippets[row] trimmedValue:80];
        } else {
            string = [_filteredSnippets[row] trimmedValue:80 includingRange:range];
        }
    } else {
        string = [_filteredSnippets[row] trimmedValue:256];
    }

    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: NSColor.textColor };
    NSAttributedString *unhighlightedAttributedString =
    [NSAttributedString attributedStringWithString:string
                                        attributes:attributes];
    textField.attributedStringValue = [self attributedString:unhighlightedAttributedString
                                     byHighlightingSubstring:self.query];

    return cellView;
}

#pragma mark Drag-Drop

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setPropertyList:@[ _filteredSnippets[row].guid ] forType:iTermSnippetsEditingPasteboardType];
    return pbItem;
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
    [self pushUndo];
    NSMutableArray<NSString *> *allGuids = [NSMutableArray array];
    [info enumerateDraggingItemsWithOptions:0 forView:aTableView classes:@[[NSPasteboardItem class]] searchOptions:@{} usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
        NSPasteboardItem *item = draggingItem.item;
        NSArray<NSString *> *guids = [item propertyListForType:iTermSnippetsEditingPasteboardType];
        [allGuids addObjectsFromArray:guids];
    }];
    [[iTermSnippetsModel sharedInstance] moveSnippetsWithGUIDs:allGuids
                                                       toIndex:row];
    return YES;
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    [self load];
    [_tableView reloadData];
}

@end
