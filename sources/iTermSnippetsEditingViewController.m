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
#import "NSView+iTerm.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const iTermSnippetsEditingPasteboardType = @"com.googlecode.iterm2.iTermSnippetsEditingPasteboardType";

@interface iTermSnippetsEditingView: NSView
@end

@implementation iTermSnippetsEditingView
@end

@interface iTermSnippetsEditingViewController ()<NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSMenuItemValidation>
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

- (void)awakeFromNib {
    [super awakeFromNib];
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Duplicate"
                                             action:@selector(duplicateSnippets:)
                                      keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Delete"
                                             action:@selector(deleteSnippets:)
                                      keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Add Above"
                                             action:@selector(addSnippetAbove:)
                                      keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Add Below"
                                             action:@selector(addSnippetBelow:)
                                      keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Edit"
                                             action:@selector(editClickedSnippet:)
                                      keyEquivalent:@""]];
    _tableView.menu = menu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(duplicateSnippets:) ||
        menuItem.action == @selector(deleteSnippets:)) {
        return [self targetSnippetIndexesForContextMenuAction].count > 0;
    }
    if (menuItem.action == @selector(editClickedSnippet:) ||
        menuItem.action == @selector(addSnippetAbove:) ||
        menuItem.action == @selector(addSnippetBelow:)) {
        return [_tableView clickedRow] >= 0;
    }
    return NO;
}

- (NSIndexSet *)targetSnippetIndexesForContextMenuAction {
    const NSInteger i = _tableView.clickedRow;
    if (i >= 0) {
        if ([[_tableView selectedRowIndexes] containsIndex:i]) {
            // Clicked on a selected snippet so apply the action to all selected snippets.
            return _tableView.selectedRowIndexes;
        }
        // Clicked on a non-selected snippet so apply the action only to the clicked one.
        return [NSIndexSet indexSetWithIndex:i];
    } else {
        // You didn't actually click on any row so apply the action to selected snippets.
        // I'm not sure this is reachable but you never know with AppKit.
        return _tableView.selectedRowIndexes;
    }
}

- (NSArray<iTermSnippet *> *)targetSnippetsForContextMenuAction {
    return [_filteredSnippets objectsAtIndexes:[self targetSnippetIndexesForContextMenuAction]];
}

- (void)duplicateSnippets:(id)sender {
    NSIndexSet *indexes = [self targetSnippetIndexesForContextMenuAction];
    NSArray<iTermSnippet *> *original = [_filteredSnippets objectsAtIndexes:indexes];
    const NSInteger lastIndex = indexes.lastIndex;
    if (lastIndex == NSNotFound) {
        return;
    }
    const NSInteger destinationIndex = lastIndex + 1;

    [self pushUndo];

    // Make copies of the snippets with new GUIDs
    NSArray<iTermSnippet *> *copies = [original mapWithBlock:^id _Nullable(iTermSnippet *snippet) {
        return [snippet clone];
    }];
    // Add them to the model
    [copies enumerateObjectsUsingBlock:^(iTermSnippet *snippet, NSUInteger idx, BOOL *stop) {
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    }];
    // Move them to the desired index.
    NSArray<NSString *> *guids = [copies mapWithBlock:^id _Nullable(iTermSnippet *snippet) {
        return snippet.guid;
    }];
    [[iTermSnippetsModel sharedInstance] moveSnippetsWithGUIDs:guids toIndex:destinationIndex];
}

- (void)deleteSnippets:(id)sender {
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] removeSnippets:[self targetSnippetsForContextMenuAction]];
}

- (void)addSnippetAbove:(id)sender {
    const NSInteger i = _tableView.clickedRow;
    if (i < 0) {
        return;
    }
    [self addSnippetAtIndex:i];
}

- (void)addSnippetAtIndex:(NSInteger)i {
    [self pushUndo];
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:nil
                                                                       completion:^(iTermSnippet * _Nullable snippet) {
        if (!snippet) {
            return;
        }
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
        [[iTermSnippetsModel sharedInstance] moveSnippetsWithGUIDs:@[ snippet.guid ] toIndex:i];
    }];
    [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (void)addSnippetBelow:(id)sender {
    const NSInteger i = _tableView.clickedRow;
    if (i < 0) {
        return;
    }
    [self addSnippetAtIndex:i + 1];
}

- (void)editClickedSnippet:(id)sender {
    const NSInteger i = _tableView.clickedRow;
    if (i < 0) {
        return;
    }
    [self editSnippet:_filteredSnippets[i]];
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
    _filteredSnippets = [[iTermSnippetsModel sharedInstance] snippetsMatchingSearchQuery:self.query
                                                                          additionalTags:@[]
                                                                               tagsFound:nil];
}

- (BOOL)snippetMatchesQuery:(iTermSnippet *)snippet {
    return [iTermSnippetsModel snippet:snippet matchesQuery:self.query];
}

- (NSInteger)unfilteredIndex:(NSInteger)filteredIndex {
    if (filteredIndex >= _filteredSnippets.count) {
        return _allSnippets.count;
    }
    iTermSnippet *snippet = _filteredSnippets[filteredIndex];
    return [_allSnippets indexOfObject:snippet];
}

- (NSInteger)filteredIndex:(NSInteger)unfilteredIndex {
    if (unfilteredIndex >= _allSnippets.count) {
        return _filteredSnippets.count;
    }
    iTermSnippet *snippet = _allSnippets[unfilteredIndex];
    return [_filteredSnippets indexOfObject:snippet];
}

- (NSIndexSet *)filteredIndexSet:(NSIndexSet *)input {
    // Convert set of unfiltered indexes to a set of GUIDs.
    NSMutableSet<NSString *> *guids = [NSMutableSet set];
    [input enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        iTermSnippet *snippet = _allSnippets[i];
        [guids addObject:snippet.guid];
    }];

    // Generate a set of filtered indexes from the set of GUIDs belonging to filtered snippets.
    NSMutableIndexSet *output = [NSMutableIndexSet indexSet];
    [_filteredSnippets enumerateObjectsUsingBlock:^(iTermSnippet * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([guids containsObject:obj.guid]) {
            [output addIndex:idx];
        }
    }];
    return output;
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
    switch (notif.mutationType) {
        case iTermSnippetsDidChangeMutationTypeEdit: {
            // Remove at notif.index
            const NSInteger removeIndex = [self filteredIndex:notif.index];
            [self load];
            NSInteger insertionIndex = NSNotFound;
            if ([_filteredSnippets containsObject:_allSnippets[notif.index]]) {
                // Add at notif.index
                insertionIndex = [self filteredIndex:notif.index];
            }
            if (removeIndex != NSNotFound || insertionIndex != NSNotFound) {
                [_tableView it_performUpdateBlock:^{
                    if (removeIndex != NSNotFound) {
                        [_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:removeIndex]
                                          withAnimation:YES];
                    }
                    if (insertionIndex != NSNotFound) {
                        [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:insertionIndex]
                                          withAnimation:NO];
                    }
                }];
            }
        }
        case iTermSnippetsDidChangeMutationTypeDeletion: {
            NSIndexSet *indexes = [self filteredIndexSet:notif.indexSet];
            [self load];
            [_tableView it_performUpdateBlock:^{
                [_tableView removeRowsAtIndexes:indexes
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeInsertion: {
            [self load];
            NSInteger i = [self filteredIndex:notif.index];
            if (i == NSNotFound) {
                i = _filteredSnippets.count;
            }
            if ([_filteredSnippets containsObject:_allSnippets[notif.index]]) {
                [_tableView it_performUpdateBlock:^{
                    [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:i]
                                      withAnimation:YES];
                }];
            }
            break;
        }
        case iTermSnippetsDidChangeMutationTypeMove: {
            NSIndexSet *sourceIndexes = [self filteredIndexSet:notif.indexSet];
            if (sourceIndexes.count == 0) {
                break;
            }
            iTermSnippet *firstSnippet = _filteredSnippets[sourceIndexes.firstIndex];

            [self load];

            [_tableView it_performUpdateBlock:^{
                const NSInteger destinationIndex = [_filteredSnippets indexOfObject:firstSnippet];
                [_tableView it_moveRowsFromSourceIndexes:sourceIndexes toRowsBeginningAtIndex:destinationIndex];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeFullReplacement:
            [self load];
            [_tableView reloadData];
            break;
    }
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
        [self editSnippet:snippet];
    }
}

- (void)editSnippet:(iTermSnippet *)snippet {
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:snippet
                                                                       completion:^(iTermSnippet * _Nullable updatedSnippet) {
        if (!updatedSnippet) {
            return;
        }
        [[iTermSnippetsModel sharedInstance] replaceSnippet:snippet withSnippet:updatedSnippet];
    }];
    [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (IBAction)import:(id)sender {
    NSOpenPanel *panel = [[NSOpenPanel alloc] init];
    panel.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@"it2snippets"] ];
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
    panel.allowedContentTypes = @[ [UTType typeWithFilenameExtension:@"it2snippets"] ];

    const NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) {
        return;
    }
    [self exportToURL:panel.URL];
}

- (IBAction)help:(id)sender {
    NSView *view = [NSView castFrom:sender];
    [view it_showWarningWithMarkdown:iTermSnippetHelpMarkdown];
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
    titleAttributedString = [titleAttributedString highlightMatchesForQuery:self.query
                                                           phraseIdentifier:@"title:"];

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
    textField.attributedStringValue = [unhighlightedAttributedString highlightMatchesForQuery:self.query
                                                                             phraseIdentifier:@"text:"];
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
                                                       toIndex:[self unfilteredIndex:row]];
    return YES;
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    [self load];
    [_tableView reloadData];
}

@end
