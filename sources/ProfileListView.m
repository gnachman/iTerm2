/*
 **  ProfileListView.m
 **  iTerm
 **
 **  Created by George Nachman on 8/26/10.
 **  Project: iTerm
 **
 **  Description: Custom view that shows a search field and table of profiles
 **    and integrates them.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 */

#import "ProfileListView.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "PTYSession.h"
#import "ProfileModel.h"
#import "ProfileModelWrapper.h"
#import "ProfileTableRow.h"
#import "ProfileTableView.h"
#import "ProfileTagsView.h"
#import "iTermSearchField.h"
#import "NSView+RecursiveDescription.h"

#define kProfileTableViewDataType @"iTerm2ProfileGuid"

NSString *const kProfileWasDeletedNotification = @"kProfileWasDeletedNotification";

const int kSearchWidgetHeight = 22;
const int kInterWidgetMargin = 10;
const CGFloat kTagsViewWidth = 0;  // TODO: remember this for each superview
const CGFloat kDefaultTagsWidth = 80;

@interface ProfileListView () <NSSearchFieldDelegate, ProfileTagsViewDelegate>
@end

@implementation ProfileListView {
    BOOL tagsViewIsCollapsed_;
    NSScrollView* scrollView_;
    iTermSearchField* searchField_;
    ProfileTableView* tableView_;
    NSTableColumn* tableColumn_;
    NSTableColumn* commandColumn_;
    NSTableColumn* shortcutColumn_;
    NSTableColumn* tagsColumn_;
    id<ProfileListViewDelegate> delegate_;
    NSSet* selectedGuids_;
    BOOL debug;
    ProfileModelWrapper *dataSource_;
    int margin_;
    ProfileTagsView *tagsView_;
    NSSplitView *splitView_;
    CGFloat lastTagsWidth_;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect model:[ProfileModel sharedInstance]];
}

// This is the designated initializer.
- (instancetype)initWithFrame:(NSRect)frameRect model:(ProfileModel*)dataSource {
    self = [super initWithFrame:frameRect];
    if (self) {
        margin_ = kInterWidgetMargin;
        [self setUnderlyingDatasource:dataSource];
        debug = NO;

        NSRect frame = [self frame];
        NSRect searchFieldFrame;
        searchFieldFrame.origin.x = 0;
        searchFieldFrame.origin.y = frame.size.height - kSearchWidgetHeight;
        searchFieldFrame.size.height = kSearchWidgetHeight;
        searchFieldFrame.size.width = frame.size.width;
        searchField_ = [[iTermSearchField alloc] initWithFrame:searchFieldFrame];
        [self _addTags:[[dataSource_ underlyingModel] allTags] toSearchField:searchField_];
        [searchField_ setDelegate:self];
        [self addSubview:searchField_];
        self.delegate = nil;

        // Split view ------------------------------------------------------------------------------
        NSRect splitViewFrame = NSMakeRect(0,
                                           0,
                                           frame.size.width,
                                           frame.size.height - kSearchWidgetHeight - margin_);
        splitView_ = [[[NSSplitView alloc] initWithFrame:splitViewFrame] autorelease];
        splitView_.vertical = YES;
        splitView_.autoresizesSubviews = NO;
        splitView_.delegate = self;
        [self addSubview:splitView_];

        // Scroll view -----------------------------------------------------------------------------
        NSRect scrollViewFrame;
        scrollViewFrame.origin.x = kTagsViewWidth + kInterWidgetMargin;
        scrollViewFrame.origin.y = 0;
        scrollViewFrame.size.width = frame.size.width - scrollViewFrame.origin.x;
        scrollViewFrame.size.height = splitViewFrame.size.height;
        scrollView_ = [[NSScrollView alloc] initWithFrame:scrollViewFrame];
        [scrollView_ setHasVerticalScroller:YES];

        // Table view ------------------------------------------------------------------------------
        NSRect tableViewFrame;
        tableViewFrame.origin.x = 0;
        tableViewFrame.origin.y = 0;

        tableViewFrame.size =
            [NSScrollView contentSizeForFrameSize:scrollViewFrame.size
                          horizontalScrollerClass:nil
                            verticalScrollerClass:[scrollView_.verticalScroller class]
                                       borderType:scrollView_.borderType
                                      controlSize:NSRegularControlSize
                                    scrollerStyle:scrollView_.verticalScroller.scrollerStyle];

        tableView_ = [[ProfileTableView alloc] initWithFrame:tableViewFrame];
        [tableView_ setMenuHandler:self];
        [tableView_ registerForDraggedTypes:[NSArray arrayWithObject:kProfileTableViewDataType]];
        [tableView_ setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
        [tableView_ setAllowsColumnResizing:YES];
        [tableView_ setAllowsColumnReordering:YES];
        [tableView_ setAllowsColumnSelection:NO];
        [tableView_ setAllowsEmptySelection:YES];
        [tableView_ setAllowsMultipleSelection:NO];
        [tableView_ setAllowsTypeSelect:NO];
        [tableView_ setBackgroundColor:[NSColor whiteColor]];

        tableColumn_ =
            [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [tableColumn_ setEditable:NO];
        [tableView_ addTableColumn:tableColumn_];

        [scrollView_ setDocumentView:tableView_];
        [scrollView_ setBorderType:NSBezelBorder];

        [tableView_ setDelegate:self];
        [tableView_ setDataSource:self];
        selectedGuids_ = [[NSMutableSet alloc] init];

        [tableView_ setDoubleAction:@selector(onDoubleClick:)];

        NSTableHeaderView* header = [[[NSTableHeaderView alloc] init] autorelease];
        [tableView_ setHeaderView:header];
        [[tableColumn_ headerCell] setStringValue:@"Profile Name"];

        [tableView_ sizeLastColumnToFit];

        [searchField_ setArrowHandler:tableView_];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadData)
                                                     name:kProfileWasDeletedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(dataChangeNotification:)
                                                     name:kReloadAddressBookNotification
                                                   object:nil];

        // Tags view -------------------------------------------------------------------------------
        NSRect tagsViewFrame = NSMakeRect(0, 0, kTagsViewWidth, splitViewFrame.size.height);
        lastTagsWidth_ = kDefaultTagsWidth;
        tagsViewIsCollapsed_ = (tagsView_.frame.size.width == 0);
        tagsView_ = [[[ProfileTagsView alloc] initWithFrame:tagsViewFrame] autorelease];
        tagsView_.delegate = self;
        [splitView_ addSubview:tagsView_];
        [splitView_ addSubview:scrollView_];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [dataSource_ release];
    [selectedGuids_ release];
    [super dealloc];
}

- (void)focusSearchField
{
    [[self window] makeFirstResponder:searchField_];
}

- (BOOL)searchFieldHasText
{
    return [[searchField_ stringValue] length] > 0;
}

#pragma mark -  Drag drop

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    // Copy guid to pboard
    NSInteger rowIndex = [rowIndexes firstIndex];
    NSMutableSet* guids = [[[NSMutableSet alloc] init] autorelease];
    while (rowIndex != NSNotFound) {
        Profile* profile = [dataSource_ profileAtIndex:rowIndex];
        NSString* guid = [profile objectForKey:KEY_GUID];
        [guids addObject:guid];
        rowIndex = [rowIndexes indexGreaterThanIndex:rowIndex];
    }

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:guids];
    [pboard declareTypes:[NSArray arrayWithObject:kProfileTableViewDataType] owner:self];
    [pboard setData:data forType:kProfileTableViewDataType];
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
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setRowOrder:)
                                        object:[self rowOrder]];
    NSPasteboard* pboard = [info draggingPasteboard];
    NSData* rowData = [pboard dataForType:kProfileTableViewDataType];
    NSSet* guids = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
    NSMutableDictionary* map = [[[NSMutableDictionary alloc] init] autorelease];

    for (NSString* guid in guids) {
        [map setObject:guid forKey:[NSNumber numberWithInt:[dataSource_ indexOfProfileWithGuid:guid]]];
    }
    NSArray* sortedIndexes = [map allKeys];
    sortedIndexes = [sortedIndexes sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber* mapIndex in sortedIndexes) {
        NSString* guid = [map objectForKey:mapIndex];

        [dataSource_ moveBookmarkWithGuid:guid toIndex:row];
        row = [dataSource_ indexOfProfileWithGuid:guid] + 1;
    }

    // Save the (perhaps partial) order of the current view in the underlying
    // model.
    [dataSource_ pushOrderToUnderlyingModel];

    // Remove the sorting order so that our change is not lost when data is
    // reloaded. This will cause a sync so it must be done after pushing the
    // local ordering to the underlying model.
    if ([[tableView_ sortDescriptors] count] > 0) {
        [tableView_ setSortDescriptors:@[]];
    }

    // The underlying model doesn't post a change notification for each bookmark
    // move because it would be overwhelming so we must do it ourselves. This
    // makes all other table views sync with the new order. First, add commands
    // to rebuild the menus.
    [self syncTableViewsWithSelectedGuids:[guids allObjects]];
    return YES;
}

- (void)syncTableViewsWithSelectedGuids:(NSArray *)guids
{
    [[dataSource_ underlyingModel] rebuildMenus];
    [[dataSource_ underlyingModel] postChangeNotification];

    NSMutableIndexSet* newIndexes = [[[NSMutableIndexSet alloc] init] autorelease];
    for (NSString* guid in guids) {
        int row = [dataSource_ indexOfProfileWithGuid:guid];
        [newIndexes addIndex:row];
    }
    [tableView_ selectRowIndexes:newIndexes byExtendingSelection:NO];

    [self reloadData];
}

// End Drag drop -------------------------------

- (void)_addTag:(id)sender {
    int itemTag = [sender tag];
    NSArray* allTags = [[[dataSource_ underlyingModel] allTags] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString* tag = [allTags objectAtIndex:itemTag];

    NSString *trimmedSearchString = [[searchField_ stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *searchStringPlusTag = [NSString stringWithFormat:@"%@ tag:%@", trimmedSearchString, tag];
    [searchField_ setStringValue:[searchStringPlusTag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:nil]];
}

- (void)_addTags:(NSArray*)tags toSearchField:(NSSearchField*)searchField
{
    NSMenu *cellMenu = [[[NSMenu alloc] initWithTitle:@"Search Menu"]
                        autorelease];
    NSMenuItem *item;

    item = [[[NSMenuItem alloc] initWithTitle:@"Tags"
                                       action:nil
                                keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [item setTag:-1];
    [cellMenu insertItem:item atIndex:0];

    NSArray* sortedTags = [tags sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (int i = 0; i < [sortedTags count]; ++i) {
        item = [[[NSMenuItem alloc] initWithTitle:[sortedTags objectAtIndex:i]
                                           action:@selector(_addTag:)
                                    keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setTag:i];
        [cellMenu insertItem:item atIndex:i+1];
    }

    [cellMenu insertItem:[NSMenuItem separatorItem] atIndex:cellMenu.numberOfItems];
    [cellMenu addItemWithTitle:@"Search Syntax Help" action:@selector(openHowToSearchHelp:) keyEquivalent:@""];

    id searchCell = [searchField cell];
    [searchCell setSearchMenuTemplate:cellMenu];

}

- (void)openHowToSearchHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/search_syntax.html"]];
}

- (void)setUnderlyingDatasource:(ProfileModel*)dataSource
{
    [dataSource_ autorelease];
    dataSource_ = [[ProfileModelWrapper alloc] initWithModel:dataSource];
}



- (ProfileModelWrapper*)dataSource
{
    return dataSource_;
}

- (void)lockSelection {
    dataSource_.lockedGuid = [self selectedGuid];
}

- (void)selectLockedSelection {
    NSInteger theIndex = [dataSource_ indexOfProfileWithGuid:dataSource_.lockedGuid];
    if (theIndex < 0) {
        return;
    }
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:theIndex] byExtendingSelection:NO];
}

- (void)unlockSelection {
    dataSource_.lockedGuid = nil;
}

#pragma mark BookmarkTableView menu handler

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([self.delegate respondsToSelector:@selector(profileTable:menuForEvent:)]) {
        return [self.delegate profileTable:self menuForEvent:theEvent];
    }
    return nil;
}

#pragma mark Undo

- (NSArray *)orderedGuids
{
    NSMutableArray* result = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < [tableView_ numberOfRows]; i++) {
        Profile* profile = [dataSource_ profileAtIndex:i];
        if (profile) {
            [result addObject:[profile objectForKey:KEY_GUID]];
        }
    }
    return result;
}

- (NSDictionary *)rowOrderWithSortDescriptors:(NSArray *)descriptors
{
    NSMutableDictionary *rowOrder = [NSMutableDictionary dictionary];
    if (descriptors) {
        [rowOrder setObject:descriptors forKey:@"descriptors"];
    }
    [rowOrder setObject:[self orderedGuids] forKey:@"guids"];
    return rowOrder;
}

- (NSDictionary *)rowOrder
{
    return [self rowOrderWithSortDescriptors:[tableView_ sortDescriptors]];
}

- (void)setRowOrder:(NSDictionary *)rowOrder
{
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setRowOrder:)
                                        object:[self rowOrder]];
    NSArray *selectedGuids = [[self selectedGuids] allObjects];
    NSArray *descriptors = [rowOrder objectForKey:@"descriptors"];
    if (descriptors) {
        [tableView_ setSortDescriptors:descriptors];
    }
    NSArray *guids = [rowOrder objectForKey:@"guids"];
    for (int i = 0; i < [guids count]; i++) {
        [[dataSource_ underlyingModel] moveGuid:[guids objectAtIndex:i] toRow:i];
    }
    [self syncTableViewsWithSelectedGuids:selectedGuids];
}

#pragma mark NSTableView data source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [dataSource_ numberOfBookmarks];
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setRowOrder:)
                                        object:[self rowOrderWithSortDescriptors:oldDescriptors]];

    [dataSource_ setSortDescriptors:[aTableView sortDescriptors]];
    [dataSource_ sort];
    [dataSource_ pushOrderToUnderlyingModel];
    [[dataSource_ underlyingModel] postChangeNotification];

    // Update the sort indicator image for all columns.
    NSArray* sortDescriptors = [dataSource_ sortDescriptors];
    for (NSTableColumn* col in [aTableView tableColumns]) {
        [aTableView setIndicatorImage:nil inTableColumn:col];
    }
    if ([sortDescriptors count] > 0) {
        NSSortDescriptor* primarySortDesc = [sortDescriptors objectAtIndex:0];
        [aTableView setIndicatorImage:([primarySortDesc ascending] ?
                                       [NSImage imageNamed:@"NSAscendingSortIndicator"] :
                                       [NSImage imageNamed:@"NSDescendingSortIndicator"])
                        inTableColumn:[aTableView tableColumnWithIdentifier:[primarySortDesc key]]];
    }

    [self reloadData];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex {
    NSCell *cell = [tableView preparedCellAtColumn:[[tableView tableColumns] indexOfObject:tableColumn_]
                                               row:rowIndex];
    NSRect constrainedBounds = NSMakeRect(0, 0, tableColumn_.width, CGFLOAT_MAX);
    NSSize naturalSize = [cell cellSizeForBounds:constrainedBounds];

    // I have no idea why I need extraHeight but maybe cellSizeForBounds: doesn't center content
    // properly with attributed strings.
    return naturalSize.height + [self extraHeight];
}

- (CGFloat)extraHeight {
    if (self.mainFont.pointSize <= [NSFont smallSystemFontSize]) {
        return 1;
    } else {
        return 2;
    }
}

- (NSFont *)mainFont {
    return [[tableColumn_ dataCell] font];
}

- (NSFont *)tagFont {
    CGFloat reduction = 0;
    if (self.mainFont.pointSize <= [NSFont smallSystemFontSize]) {
        reduction = 2;
    } else {
        reduction = 3;
    }
    return [NSFont systemFontOfSize:self.mainFont.pointSize - reduction];
}

- (NSAttributedString *)attributedStringForName:(NSString *)name
                                           tags:(NSArray *)tags
                                       selected:(BOOL)selected
                                      isDefault:(BOOL)isDefault
                                         filter:(NSString *)filter {
    NSColor *textColor;
    NSColor *tagColor;
    NSColor *highlightedBackgroundColor;
    if (selected) {
        if ([NSApp isActive] && self.window.isKeyWindow) {
            textColor = [NSColor whiteColor];
        } else {
            textColor = [NSColor blackColor];
        }
        tagColor = [NSColor whiteColor];
        highlightedBackgroundColor = [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:0.4];
    } else {
        textColor = [NSColor blackColor];
        tagColor = [NSColor colorWithCalibratedWhite:0.5 alpha:1];
        highlightedBackgroundColor = [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:0.4];
    }
    NSDictionary* plainAttributes = @{ NSForegroundColorAttributeName: textColor,
                                       NSFontAttributeName: self.mainFont };
    NSDictionary* highlightedNameAttributes = @{ NSForegroundColorAttributeName: textColor,
                                                 NSBackgroundColorAttributeName: highlightedBackgroundColor,
                                                 NSFontAttributeName: self.mainFont };
    NSDictionary* smallAttributes = @{ NSForegroundColorAttributeName: tagColor,
                                       NSFontAttributeName: self.tagFont };
    NSDictionary* highlightedSmallAttributes = @{ NSForegroundColorAttributeName: tagColor,
                                                  NSBackgroundColorAttributeName: highlightedBackgroundColor,
                                                  NSFontAttributeName: self.tagFont };
    NSMutableAttributedString *theAttributedString =
        [[[ProfileModel attributedStringForName:name
                   highlightingMatchesForFilter:filter
                              defaultAttributes:plainAttributes
                          highlightedAttributes:highlightedNameAttributes] mutableCopy] autorelease];

    if (isDefault) {
        NSAttributedString *star = [[[NSAttributedString alloc] initWithString:@"★ "
                                                                    attributes:plainAttributes] autorelease];
        [theAttributedString insertAttributedString:star atIndex:0];
    }

    if (tags.count) {
        NSAttributedString *newline = [[[NSAttributedString alloc] initWithString:@"\n"
                                                                       attributes:plainAttributes] autorelease];
        [theAttributedString appendAttributedString:newline];

        NSArray *attributedTags = [ProfileModel attributedTagsForTags:tags
                                         highlightingMatchesForFilter:filter
                                                    defaultAttributes:smallAttributes
                                                highlightedAttributes:highlightedSmallAttributes];
        NSAttributedString *comma =
            [[[NSAttributedString alloc] initWithString:@", " attributes:smallAttributes] autorelease];
        for (NSAttributedString *attributedTag in attributedTags) {
            [theAttributedString appendAttributedString:attributedTag];
            if (attributedTag != attributedTags.lastObject) {
                [theAttributedString appendAttributedString:comma];
            }
        }
    }

    return theAttributedString;
}

- (NSAttributedString *)attributedStringForString:(NSString *)string selected:(BOOL)selected {
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
                                  NSForegroundColorAttributeName: (selected && [NSApp isActive] && self.window.isKeyWindow) ? [NSColor whiteColor] : [NSColor blackColor] };
    return [[[NSAttributedString alloc] initWithString:string attributes:attributes] autorelease];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                          row:(NSInteger)rowIndex {
    Profile* bookmark = [dataSource_ profileAtIndex:rowIndex];

    if (aTableColumn == tableColumn_) {
        DLog(@"Getting name of profile at row %d. The dictionary's address is %p. Its name is %@",
             (int)rowIndex, bookmark, bookmark[KEY_NAME]);
        Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];
        return [self attributedStringForName:bookmark[KEY_NAME]
                                        tags:bookmark[KEY_TAGS]
                                    selected:[[tableView_ selectedRowIndexes] containsIndex:rowIndex]
                                   isDefault:[bookmark[KEY_GUID] isEqualToString:defaultProfile[KEY_GUID]]
                                      filter:[searchField_ stringValue]];
    } else if (aTableColumn == commandColumn_) {
        NSString *theString = nil;
        if (![[bookmark objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"]) {
            theString = @"Login shell";
        } else {
            theString = [bookmark objectForKey:KEY_COMMAND_LINE];
        }
        return [self attributedStringForString:theString
                                      selected:[[tableView_ selectedRowIndexes] containsIndex:rowIndex]];
    } else if (aTableColumn == shortcutColumn_) {
        NSString* key = [bookmark objectForKey:KEY_SHORTCUT];
        if ([key length]) {
            NSString *theString = [NSString stringWithFormat:@"^⌘%@", [bookmark objectForKey:KEY_SHORTCUT]];
            return [self attributedStringForString:theString
                                          selected:[[tableView_ selectedRowIndexes] containsIndex:rowIndex]];
        } else {
            return @"";
        }
    } else {
        return nil;
    }

    return @"";
}

// Delegate methods
- (void)tableView:(NSTableView *)aTableView didClickTableColumn:(NSTableColumn *)aTableColumn {
    NSMutableArray* newSortDescriptors = [NSMutableArray arrayWithArray:[tableView_ sortDescriptors]];
    BOOL done = NO;
    BOOL ascending = YES;
    // Find the existing sort descriptor for the clicked-on column and move it
    // to the front.
    for (int i = 0; i < [newSortDescriptors count]; ++i) {
        NSSortDescriptor* desc = [newSortDescriptors objectAtIndex:i];
        if ([[desc key] isEqualToString:[aTableColumn identifier]]) {
            ascending = ![desc ascending];
            [newSortDescriptors removeObjectAtIndex:i];
            [newSortDescriptors insertObject:[[[NSSortDescriptor alloc] initWithKey:[aTableColumn identifier]
                                                                          ascending:ascending] autorelease]
                                     atIndex:0];
            done = YES;
            break;
        }
    }

    if (!done) {
        // This column was not previously sorted. Add it to the head of the array.
        [newSortDescriptors insertObject:[[[NSSortDescriptor alloc] initWithKey:[aTableColumn identifier]
                                                                      ascending:YES] autorelease]
                                 atIndex:0];
    }
    [tableView_ setSortDescriptors:newSortDescriptors];

    [aTableView reloadData];
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(profileTableSelectionWillChange:)]) {
        [self.delegate profileTableSelectionWillChange:self];
    }
    return YES;
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification
{
    // Mouse is being dragged across rows
    if (self.delegate && [self.delegate respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
        [self.delegate profileTableSelectionDidChange:self];
    }
    [selectedGuids_ release];
    selectedGuids_ = [self selectedGuids];
    [selectedGuids_ retain];
}

- (void)setHasSelection:(BOOL)value
{
    // Placeholder for key-value observation
}

- (BOOL)hasSelection
{
    return [tableView_ numberOfSelectedRows] > 0;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    // There was a click on a row
    if (self.delegate && [self.delegate respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
        [self.delegate profileTableSelectionDidChange:self];
    }
    dataSource_.lockedGuid = nil;
    [selectedGuids_ release];
    selectedGuids_ = [self selectedGuids];
    [selectedGuids_ retain];
    // tweak key value observation
    [self setHasSelection:[selectedGuids_ count] > 0];
}

- (NSInteger)selectedRow {
    return [tableView_ selectedRow];
}

- (void)reloadData {
    DLog(@"ProfileListView reloadData called");
    [self _addTags:[[dataSource_ underlyingModel] allTags] toSearchField:searchField_];
    [dataSource_ sync];
    DLog(@"calling reloadData on the profile tableview");
    [tableView_ reloadData];
    if (self.delegate && ![selectedGuids_ isEqualToSet:[self selectedGuids]]) {
        [selectedGuids_ release];
        selectedGuids_ = [self selectedGuids];
        [selectedGuids_ retain];
        if ([self.delegate respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
            [self.delegate profileTableSelectionDidChange:self];
        }
    }
}

- (void)selectRowIndex:(int)theRow
{
    NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:theRow];
    [tableView_ selectRowIndexes:indexes byExtendingSelection:NO];
    [tableView_ scrollRowToVisible:theRow];
}

- (void)selectRowByGuid:(NSString*)guid
{
    int theRow = [dataSource_ indexOfProfileWithGuid:guid];
    if (theRow == -1) {
        [self deselectAll];
        return;
    }
    [self selectRowIndex:theRow];
}

- (NSInteger)numberOfRows {
    return [dataSource_ numberOfBookmarks];
}

- (void)clearSearchField {
    [searchField_ setStringValue:@""];
    [self updateResultsForSearch];
}

- (void)allowEmptySelection
{
    [tableView_ setAllowsEmptySelection:YES];
}

- (void)allowMultipleSelections
{
    [tableView_ setAllowsMultipleSelection:YES];
}

- (void)deselectAll
{
    [tableView_ deselectAll:self];
}

- (NSString*)selectedGuid
{
    int row = [self selectedRow];
    if (row < 0) {
        return nil;
    }
    Profile* bookmark = [dataSource_ profileAtIndex:row];
    if (!bookmark) {
        return nil;
    }
    return [bookmark objectForKey:KEY_GUID];
}

- (NSArray *)orderedSelectedGuids
{
    NSMutableArray* result = [[[NSMutableArray alloc] init] autorelease];
    NSIndexSet* indexes = [tableView_ selectedRowIndexes];
    NSUInteger theIndex = [indexes firstIndex];
    while (theIndex != NSNotFound) {
        Profile* bookmark = [dataSource_ profileAtIndex:theIndex];
        if (bookmark) {
            [result addObject:[bookmark objectForKey:KEY_GUID]];
        }

        theIndex = [indexes indexGreaterThanIndex:theIndex];
    }
    return result;
}

- (NSSet*)selectedGuids
{
    return [NSSet setWithArray:[self orderedSelectedGuids]];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    dataSource_.lockedGuid = nil;
    [self updateResultsForSearch];
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    return @[];
}

- (void)updateResultsForSearch
{
    // search field changed
    [dataSource_ setFilter:[searchField_ stringValue]];
    [self reloadData];
    if ([self selectedRow] < 0 && [self numberOfRows] > 0) {
        [self selectRowIndex:0];
        [tableView_ scrollRowToVisible:0];
    }
    if ([self.delegate respondsToSelector:@selector(profileTableFilterDidChange:)]) {
        [self.delegate profileTableFilterDidChange:self];
    }
}

- (void)multiColumns
{
    shortcutColumn_ = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    [shortcutColumn_ setEditable:NO];
    [shortcutColumn_ setWidth:50];
    [tableView_ addTableColumn:shortcutColumn_];

    commandColumn_ = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    [commandColumn_ setEditable:NO];
    [tableView_ addTableColumn:commandColumn_];

    [tableColumn_ setWidth:250];

    [[shortcutColumn_ headerCell] setStringValue:@"Shortcut"];
    [[commandColumn_ headerCell] setStringValue:@"Command"];
    [tableView_ sizeLastColumnToFit];
}

- (void)dataChangeNotification:(id)sender {
    DLog(@"Scheduling a delayed perform of reloadData");
    // Use a delayed perform so the underlying model has a chance to parse its journal.
    [self performSelector:@selector(reloadData)
               withObject:nil
               afterDelay:0];
}

- (void)onDoubleClick:(id)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(profileTableRowSelected:)]) {
        [self.delegate profileTableRowSelected:self];
    }
}

- (void)eraseQuery {
    [searchField_ setStringValue:@""];
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
                                                             object:nil]];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize
{
    NSRect frame = [self frame];

    NSRect searchFieldFrame;
    searchFieldFrame.origin.x = 0;
    searchFieldFrame.origin.y = frame.size.height - kSearchWidgetHeight;
    searchFieldFrame.size.height = kSearchWidgetHeight;
    searchFieldFrame.size.width = frame.size.width;
    [searchField_ setFrame:searchFieldFrame];

    NSRect splitViewFrame = NSMakeRect(0,
                                       0,
                                       frame.size.width,
                                       frame.size.height - kSearchWidgetHeight - margin_);
    splitView_.frame = splitViewFrame;
}

- (void)turnOnDebug
{
    NSLog(@"Debugging object at %p. Current count is %d", (void*)self, (int)[self retainCount]);
    debug=YES;
}

- (NSTableView*)tableView
{
    return tableView_;
}

- (void)setFont:(NSFont *)theFont
{
    for (NSTableColumn *col in [tableView_ tableColumns]) {
        [[col dataCell] setFont:theFont];
    }

    if ([theFont pointSize] < 13) {
        [[searchField_ cell] setFont:theFont];
        [[searchField_ cell] setControlSize:NSSmallControlSize];
        [searchField_ sizeToFit];

        margin_ = 5;
        [self resizeSubviewsWithOldSize:self.frame.size];
    }
    [tagsView_ setFont:theFont];
    [tableView_ reloadData];
}

- (void)disableArrowHandler
{
    [searchField_ setArrowHandler:nil];
}

- (void)toggleTags {
    [self setTagsOpen:!self.tagsVisible animated:YES];
}

- (void)setTagsOpen:(BOOL)open animated:(BOOL)animated {
    if (open == self.tagsVisible) {
        return;
    }
    NSRect newTableFrame = tableView_.frame;
    NSRect newTagsFrame = tagsView_.frame;
    CGFloat newTagsWidth;
    if (open) {
        newTagsWidth = lastTagsWidth_;
    } else {
        lastTagsWidth_ = tagsView_.frame.size.width;
        newTagsWidth = 0;
    }
    newTableFrame.size.width =  self.frame.size.width - newTagsWidth;
    newTagsFrame.size.width = newTagsWidth;
    if (animated) {
        [tagsView_.animator setFrame:newTagsFrame];
        [tableView_.animator setFrame:newTableFrame];
    } else {
        tagsView_.frame = newTagsFrame;
        tableView_.frame = newTableFrame;
    }
}

- (BOOL)tagsVisible {
    return tagsView_.frame.size.width > 0;
}

#pragma mark - ProfileTagsViewDelegate

- (void)profileTagsViewSelectionDidChange:(ProfileTagsView *)profileTagsView {
    searchField_.stringValue = [profileTagsView.selectedTags componentsJoinedByString:@" "];
    [self updateResultsForSearch];
}

#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if ((tagsView_.frame.size.width == 0) != tagsViewIsCollapsed_ &&
        [self.delegate respondsToSelector:@selector(profileTableTagsVisibilityDidChange:)]) {
        [self.delegate profileTableTagsVisibilityDidChange:self];
    }
    tagsViewIsCollapsed_ = (tagsView_.frame.size.width == 0);
}
@end
