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
#import "iTermSplitViewAnimation.h"
#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PTYSession.h"
#import "ProfileModel.h"
#import "ProfileModelWrapper.h"
#import "ProfileTableRow.h"
#import "ProfileTableView.h"
#import "ProfileTagsView.h"
#import "iTermSearchField.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+iTerm.h"

#define kProfileTableViewDataType @"iTerm2ProfileGuid"

// NSAttributedString attribute keys used as source values by
// iTermProfileListViewTextField. One of these colors will be used as the
// NSForegroundColorAttributeName's value when the background style changes.
static NSString *const iTermSelectedActiveForegroundColor = @"iTermSelectedActiveForegroundColor";
static NSString *const iTermRegularForegroundColor = @"iTermRegularForegroundColor";
static NSString *const iTermProfileListViewRestorableStateTagsVisible = @"iTermProfileListViewRestorableStateTagsVisible";
static NSString *const iTermProfileListViewRestorableStateTagsFraction = @"iTermProfileListViewRestorableStateTagsFraction";

// This is a text field that updates its text colors depending on the current background style.
@interface iTermProfileListViewTextField : NSTextField
@end

@implementation iTermProfileListViewTextField

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    switch (backgroundStyle) {
        case NSBackgroundStyleNormal:
            self.textColor = [NSColor labelColor];
            [self setAttributedTextColorsForKey:iTermRegularForegroundColor];
            break;
        case NSBackgroundStyleEmphasized:
            [self setAttributedTextColorsForKey:iTermSelectedActiveForegroundColor];
            self.textColor = [NSColor labelColor];
            break;

        case NSBackgroundStyleRaised:
        case NSBackgroundStyleLowered:
            DLog(@"Unexpected background style %@", @(backgroundStyle));
            break;
    }
}

- (void)setAttributedTextColorsForKey:(NSString *)key {
    NSMutableAttributedString *m = [self.attributedStringValue.mutableCopy autorelease];
    [self.attributedStringValue enumerateAttributesInRange:NSMakeRange(0, self.attributedStringValue.string.length)
                                                   options:0
                                                usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
                                                    NSMutableDictionary *newAttrs = [[attrs mutableCopy] autorelease];
                                                    newAttrs[NSForegroundColorAttributeName] = attrs[key];
                                                    [m setAttributes:newAttrs range:range];
                                                }];
    self.attributedStringValue = m;
}

@end

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
    NSMutableDictionary<NSNumber *, NSNumber *> *_savedHeights;

    // Cached row height info
    BOOL _haveHeights;
    CGFloat _heightWithTags;
    CGFloat _heightWithoutTags;
    NSFont *_font;
    NSInteger _restoringSelection;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect model:[ProfileModel sharedInstance]];
}


- (instancetype)initWithFrame:(NSRect)frameRect model:(ProfileModel*)dataSource {
    return [self initWithFrame:frameRect model:dataSource font:nil];
}

- (instancetype)initWithFrame:(NSRect)frameRect model:(ProfileModel *)dataSource font:(NSFont *)font {
    self = [super initWithFrame:frameRect];
    if (self) {
        _savedHeights = [[NSMutableDictionary alloc] init];
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
        ITERM_IGNORE_PARTIAL_BEGIN
        [searchField_ setDelegate:self];
        ITERM_IGNORE_PARTIAL_END
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
                                      controlSize:NSControlSizeRegular
                                    scrollerStyle:scrollView_.verticalScroller.scrollerStyle];

        tableView_ = [[ProfileTableView alloc] initWithFrame:tableViewFrame];
#ifdef MAC_OS_X_VERSION_10_16
        if (@available(macOS 10.16, *)) {
            tableView_.style = NSTableViewStyleInset;
        }
#endif
        [tableView_ setMenuHandler:self];
        [tableView_ registerForDraggedTypes:[NSArray arrayWithObject:kProfileTableViewDataType]];
        [tableView_ setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
        [tableView_ setAllowsColumnResizing:YES];
        [tableView_ setAllowsColumnReordering:YES];
        [tableView_ setAllowsColumnSelection:NO];
        [tableView_ setAllowsEmptySelection:YES];
        [tableView_ setAllowsMultipleSelection:NO];
        [tableView_ setAllowsTypeSelect:NO];

        tableColumn_ =
            [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [tableColumn_ setEditable:NO];
        [tableView_ addTableColumn:tableColumn_];

        [scrollView_ setDocumentView:tableView_];
        if (@available(macOS 10.16, *)) {
            scrollView_.borderType = NSLineBorder;
        } else {
            [scrollView_ setBorderType:NSBezelBorder];
        }

        selectedGuids_ = [[NSMutableSet alloc] init];

        [tableView_ setDoubleAction:@selector(onDoubleClick:)];

        tableColumn_.title = @"Profile Name";

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

        if (font) {
            [self setFont:font];
        }
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_savedHeights release];
    [dataSource_ release];
    [selectedGuids_ release];
    // These if statements are pure paranoia because this thing gets used all
    // over the place and is pretty old.
    if (tableView_.delegate == self) {
        tableView_.delegate = nil;
    }
    if (tableView_.dataSource == self) {
        tableView_.dataSource = nil;
    }
    [_font release];
    [super dealloc];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    DLog(@"ProfileListView: performKeyEquivalent: %@", event);
    BOOL result = [super performKeyEquivalent:event];
    DLog(@"ProfileListView: performKeyEquivalent: returns %@", @(result));
    return result;
}

- (void)forceOverlayScroller {
    scrollView_.scrollerStyle = NSScrollerStyleOverlay;
    tagsView_.scrollView.scrollerStyle = NSScrollerStyleOverlay;
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

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:guids
                                         requiringSecureCoding:NO
                                                         error:nil];
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

    NSError *error = nil;
    NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingFromData:rowData error:&error] autorelease];
    if (error) {
        return NO;
    }
    NSSet<NSString *> *guids = [unarchiver decodeObjectOfClass:[NSSet class] forKey:NSKeyedArchiveRootObjectKey];
    if (!guids) {
        return NO;
    }
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

    [self selectGuids:guids];

    [self reloadData];
}

- (void)selectGuids:(NSArray *)guids {
    NSMutableIndexSet* newIndexes = [[[NSMutableIndexSet alloc] init] autorelease];
    for (NSString* guid in guids) {
        int row = [dataSource_ indexOfProfileWithGuid:guid];
        [newIndexes addIndex:row];
    }
    [tableView_ selectRowIndexes:newIndexes byExtendingSelection:NO];
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

- (CGFloat)heightOfRowWithTags:(BOOL)hasTags {
    if (!_haveHeights) {
        _heightWithTags = [[self attributedStringForName:@"Mj"
                                                    tags:@[ @"Mj" ]
                                                selected:NO
                                               isDefault:YES
                                                  filter:nil] heightForWidth:100] + [self extraHeightWithTags:YES];
        _heightWithoutTags = [[self attributedStringForName:@"Mj"
                                                       tags:nil
                                                   selected:NO
                                                  isDefault:YES
                                                     filter:nil] heightForWidth:100] + [self extraHeightWithTags:NO];
        _haveHeights = YES;
    }
    return hasTags ? _heightWithTags : _heightWithoutTags;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex {
    Profile *profile = [dataSource_ profileAtIndex:rowIndex];
    const BOOL hasTags = ([profile[KEY_TAGS] count] > 0);
    CGFloat height = [self heightOfRowWithTags:hasTags];
    _savedHeights[@(rowIndex)] = @(height);
    return height;
}

- (CGFloat)extraHeightWithTags:(BOOL)hasTags {
    if (hasTags) {
        return 6;
    } else {
        return 2;
    }
}

- (NSFont *)mainFont {
    return _font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
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

- (BOOL)lightTheme {
    return ![self.window.appearance.name isEqual:NSAppearanceNameVibrantDark];
}

- (NSColor *)regularTextColor {
    return [NSColor labelColor];
}

- (NSColor *)textColorWhenInactiveAndSelected {
    return [NSColor unemphasizedSelectedTextColor];
}

- (NSColor *)selectedActiveTagColor {
    return [NSColor selectedMenuItemTextColor];
}

- (NSColor *)selectedActiveTextColor {
    return [NSColor selectedMenuItemTextColor];
}

- (NSColor *)regularTagColor {
    return [NSColor colorWithCalibratedWhite:0.5 alpha:1];
}

- (NSAttributedString *)attributedStringForName:(NSString *)name
                                           tags:(NSArray *)tags
                                       selected:(BOOL)selected
                                      isDefault:(BOOL)isDefault
                                         filter:(NSString *)filter {
    NSColor *highlightedBackgroundColor = [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:0.4];

    NSColor *textColor = [self regularTextColor];
    NSColor *highlightedTextColor = [NSColor blackColor];
    NSColor *tagColor = [self regularTagColor];
    NSColor *selectedActiveTextColor = [self selectedActiveTextColor];
    NSColor *selectedActiveTagColor = [self selectedActiveTagColor];
    
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary* plainAttributes = @{ iTermSelectedActiveForegroundColor: selectedActiveTextColor,
                                       iTermRegularForegroundColor: textColor,
                                       NSParagraphStyleAttributeName: paragraphStyle,
                                       NSFontAttributeName: self.mainFont };
    NSDictionary* highlightedNameAttributes = @{ iTermSelectedActiveForegroundColor: selectedActiveTextColor,
                                                 iTermRegularForegroundColor: highlightedTextColor,
                                                 NSParagraphStyleAttributeName: paragraphStyle,
                                                 NSBackgroundColorAttributeName: highlightedBackgroundColor,
                                                 NSFontAttributeName: self.mainFont };
    NSDictionary* smallAttributes = @{ iTermSelectedActiveForegroundColor: selectedActiveTagColor,
                                       iTermRegularForegroundColor: tagColor,
                                       NSParagraphStyleAttributeName: paragraphStyle,
                                       NSFontAttributeName: self.tagFont };
    NSDictionary* highlightedSmallAttributes = @{ iTermSelectedActiveForegroundColor: selectedActiveTagColor,
                                                  iTermRegularForegroundColor: highlightedTextColor,
                                                  NSParagraphStyleAttributeName: paragraphStyle,
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
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSColor *textColor = [self regularTextColor];
    NSColor *selectedActiveTextColor = [self selectedActiveTextColor];

    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
                                  NSParagraphStyleAttributeName: paragraphStyle,
                                  iTermSelectedActiveForegroundColor: selectedActiveTextColor,
                                  iTermRegularForegroundColor: textColor };
    return [[[NSAttributedString alloc] initWithString:string ?: @"" attributes:attributes] autorelease];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    static NSString *const identifier = @"ProfileListViewIdentifier";
    BOOL multiline = NO;
    id value = [self stringOrAttributedStringForColumn:tableColumn row:row multiline:&multiline];
    NSTableCellView *result;
    if ([value isKindOfClass:[NSAttributedString class]]) {
        result = [tableView newTableCellViewWithTextFieldUsingIdentifier:identifier attributedString:value];
        result.textField.toolTip = [value string];
    } else {
        result = [tableView newTableCellViewWithTextFieldUsingIdentifier:identifier font:_font string:value];
        result.textField.toolTip = value;
    }
    return result;
}

- (id)stringOrAttributedStringForColumn:(NSTableColumn *)aTableColumn
                                    row:(NSInteger)rowIndex
                              multiline:(BOOL *)multilinePtr {
    Profile* bookmark = [dataSource_ profileAtIndex:rowIndex];

    *multilinePtr = 0;
    if (aTableColumn == tableColumn_) {
        DLog(@"Getting name of profile at row %d. The dictionary's address is %p. Its name is %@",
             (int)rowIndex, bookmark, bookmark[KEY_NAME]);
        Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];
        *multilinePtr = [bookmark[KEY_TAGS] count] > 0;
        return [self attributedStringForName:bookmark[KEY_NAME] ?: @""
                                        tags:bookmark[KEY_TAGS]
                                    selected:[[tableView_ selectedRowIndexes] containsIndex:rowIndex]
                                   isDefault:[bookmark[KEY_GUID] isEqualToString:defaultProfile[KEY_GUID]]
                                      filter:[searchField_ stringValue]];
    } else if (aTableColumn == commandColumn_) {
        NSString *theString = nil;
        NSString *customCommand = bookmark[KEY_CUSTOM_COMMAND];
        if ([customCommand isEqualToString:kProfilePreferenceCommandTypeCustomValue] ||
            [customCommand isEqualToString:kProfilePreferenceCommandTypeCustomShellValue]) {
            theString = [bookmark objectForKey:KEY_COMMAND_LINE];
        } else if ([customCommand isEqualToString:kProfilePreferenceCommandTypeLoginShellValue]) {
            theString = @"Login shell";
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
    if (_restoringSelection) {
        // After reloadData, setting selection back to what it was.
        return;
    }

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
    NSSet *newSelectedGuids = [NSSet setWithArray:[selectedGuids_.allObjects filteredArrayUsingBlock:^BOOL(id guid) {
        return ([dataSource_ indexOfProfileWithGuid:guid] != -1);
    }]];
    if (self.delegate && [selectedGuids_ isEqualToSet:newSelectedGuids]) {
        // No change to selection. Don't tell the delegate.
        _restoringSelection++;
        [self selectGuids:newSelectedGuids.allObjects];
        _restoringSelection--;
    } else {
        if (self.delegate && ![selectedGuids_ isEqualToSet:newSelectedGuids]) {
            // Selection is changing.
            [selectedGuids_ release];
            selectedGuids_ = newSelectedGuids;
            [selectedGuids_ retain];
            if ([self.delegate respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
                [self.delegate profileTableSelectionDidChange:self];
            }
        }

        // Selection changed or there is no delegate.
        [self selectGuids:newSelectedGuids.allObjects];
     }
}

- (void)selectRowIndex:(int)theRow {
    if (theRow >= (int)tableView_.numberOfRows) {
        return;
    }
    NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:theRow];
    // Make sure the rowview exists so its background style can be known when
    // the NSTableCellView is created.
    [tableView_ rowViewAtRow:theRow makeIfNecessary:YES];
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

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(cancelOperation:)) {
        if (searchField_.stringValue.length == 0) {
            return NO;
        }
        searchField_.stringValue = @"";
        dataSource_.lockedGuid = nil;
        [self updateResultsForSearch];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:) &&
        (self.numberOfRows == 1 || tableView_.selectedRow != -1) &&
        [self.delegate respondsToSelector:@selector(profileTableRowSelected:)]) {
        if (tableView_.selectedRow == -1) {
            [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        }
        [self.delegate profileTableRowSelected:self];
        return YES;
    }
    return NO;
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

    shortcutColumn_.title = @"Shortcut";
    commandColumn_.title = @"Command";
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

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize {
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

    if (tableView_.delegate) {
        NSMutableIndexSet *rowsWithHeightChange = [NSMutableIndexSet indexSet];
        for (NSInteger i = 0; i < self.numberOfRows; i++) {
            CGFloat savedHeight = [_savedHeights[@(i)] doubleValue];
            CGFloat height = [self tableView:tableView_ heightOfRow:i];
            if (round(height) != round(savedHeight)) {
                [rowsWithHeightChange addIndex:i];
            }
        }
        if (rowsWithHeightChange.count > 0) {
            [tableView_ noteHeightOfRowsWithIndexesChanged:rowsWithHeightChange];
        }
    }
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
    _haveHeights = NO;
    [_font autorelease];
    _font = [theFont retain];

    if ([theFont pointSize] < 13) {
        [[searchField_ cell] setFont:theFont];
        [[searchField_ cell] setControlSize:NSControlSizeSmall];
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
    CGFloat newTagsWidth;
    if (open) {
        newTagsWidth = lastTagsWidth_;
    } else {
        lastTagsWidth_ = tagsView_.frame.size.width;
        newTagsWidth = 0;
    }
    const CGFloat oldDividerPosition = NSWidth(tagsView_.frame);
    if (animated) {
        [[[[iTermSplitViewAnimation alloc] initWithSplitView:splitView_
                                              dividerAtIndex:0
                                                        from:oldDividerPosition
                                                          to:newTagsWidth
                                                    duration:0.125
                                                  completion:nil] autorelease] startAnimation];
    } else {
        [splitView_.animator setPosition:newTagsWidth ofDividerAtIndex:0];
    }
}

- (BOOL)tagsVisible {
    return tagsView_.frame.size.width > 0;
}

- (CGFloat)tagsFraction {
    return tagsView_.frame.size.width / splitView_.frame.size.width;
}

- (void)setTagsFraction:(CGFloat)tagsFraction {
    NSRect rect = tagsView_.frame;
    rect.size.width = tagsFraction * splitView_.frame.size.width;
    tagsView_.frame = rect;

    rect = scrollView_.frame;
    rect.origin.x = NSMaxX(tagsView_.frame) + splitView_.dividerThickness;
    rect.size.width = NSWidth(splitView_.frame) - NSMinX(rect);
    scrollView_.frame = rect;
    
    [splitView_ adjustSubviews];
}

- (NSDictionary *)restorableState {
    return @{ iTermProfileListViewRestorableStateTagsVisible: @(self.tagsVisible),
              iTermProfileListViewRestorableStateTagsFraction: @(self.tagsFraction) };
}

- (void)restoreFromState:(NSDictionary *)state {
    if (!state) {
        return;
    }
    const CGFloat fraction = [NSNumber castFrom:state[iTermProfileListViewRestorableStateTagsFraction]].doubleValue;
    if ([state[iTermProfileListViewRestorableStateTagsVisible] boolValue] && fraction > 0 & fraction <= 1) {
        [self setTagsOpen:YES animated:NO];
        self.tagsFraction = fraction;
    }
}

#pragma mark - ProfileTagsViewDelegate

- (void)profileTagsViewSelectionDidChange:(ProfileTagsView *)profileTagsView {
    searchField_.stringValue =
        [[profileTagsView.selectedTags mapWithBlock:^id(NSString *tag) {
            return [@"tag:" stringByAppendingString:tag];
        }] componentsJoinedByString:@" "];
    [self updateResultsForSearch];
}

#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if ((tagsView_.frame.size.width == 0) != tagsViewIsCollapsed_ &&
        [self.delegate respondsToSelector:@selector(profileTableTagsVisibilityDidChange:)]) {
        [self.delegate profileTableTagsVisibilityDidChange:self];
    }
    tagsViewIsCollapsed_ = (tagsView_.frame.size.width == 0);
    [self.window invalidateRestorableState];
}

@end
