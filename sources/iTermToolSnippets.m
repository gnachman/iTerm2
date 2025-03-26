//
//  iTermToolSnippets.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermToolSnippets.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermActionsModel.h"
#import "iTermApplication.h"
#import "iTermEditSnippetWindowController.h"
#import "iTermProfileSearchToken.h"
#import "iTermSearchField.h"
#import "iTermSnippetsModel.h"
#import "iTermTuple.h"
#import "iTermCompetentTableRowView.h"

#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSStringITerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;
static NSString *const iTermToolSnippetsPasteboardType = @"com.googlecode.iterm2.iTermToolSnippetsPasteboardType";
static NSString *const iTermToolSnippetsUseOutlineViewModeUserDefaultsKey = @"NoSyncSnippetsToolUsesOutlineView";

@interface iTermSnippetFolderItem: NSObject<iTermUniquelyIdentifiable>
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSArray *children;
@property (nonatomic, copy) NSString *title;
@end

@implementation iTermSnippetFolderItem
- (NSString *)stringUniqueIdentifier {
    return _path;
}
@end

@interface iTermSnippetItem : NSObject<iTermUniquelyIdentifiable>
@property (nonatomic, strong) iTermSnippet *snippet;
@end

@implementation iTermSnippetItem
+ (instancetype)itemWithSnippet:(iTermSnippet *)snippet {
    iTermSnippetItem *item = [[self alloc] init];
    item.snippet = snippet;
    return item;
}
- (NSString *)stringUniqueIdentifier {
    return _snippet.guid;
}
@end

typedef NS_ENUM(NSUInteger, iTermToolSnippetsAction) {
    iTermToolSnippetsActionSend,
    iTermToolSnippetsActionAdvancedPaste,
    iTermToolSnippetsActionComposer
};

@interface iTermToolSnippets() <
    NSDraggingDestination,
    NSOutlineViewDataSource,
    NSOutlineViewDelegate,
    NSSearchFieldDelegate>
@end

@implementation iTermToolSnippets {
    NSScrollView *_outlineViewScrollView;
    NSOutlineView *_outlineView;

    NSButton *_applyButton;
    NSButton *_advancedPasteButton;
    NSButton *_addButton;
    NSButton *_removeButton;
    NSButton *_editButton;
    iTermSearchField *_searchField;
    NSButton *_help;

    NSArray<iTermSnippet *> *_unfilteredSnippets;
    NSArray<iTermSnippet *> *_filteredSnippets;
    NSArray *_tree;
    iTermEditSnippetWindowController *_windowController;
    BOOL _haveTags;
    CGFloat _standardRowHeight;
    NSImage *_icon;
    NSImage *_folderIcon;
}

static NSButton *iTermToolSnippetsNewButton(NSString *imageName, NSString *title, id target, SEL selector, NSRect frame) {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    if (imageName) {
        if (@available(macOS 10.16, *)) {
            button.image = [NSImage it_imageForSymbolName:imageName accessibilityDescription:title];
        } else {
            button.image = [NSImage imageNamed:imageName];
        }
    } else {
        button.title = title;
    }
    [button setTarget:target];
    [button setAction:selector];
    if (@available(macOS 10.16, *)) {
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.bordered = NO;
        button.imageScaling = NSImageScaleProportionallyUpOrDown;
        button.imagePosition = NSImageOnly;
    } else {
        [button setBezelStyle:NSBezelStyleSmallSquare];
    }
    [button sizeToFit];
    [button setAutoresizingMask:NSViewMinYMargin];

    return button;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(macOS 11.0, *)) {
            _icon = [NSImage imageWithSystemSymbolName:@"text.document.fill" accessibilityDescription:@"Snippet icon"];
            _folderIcon = [NSImage imageWithSystemSymbolName:@"folder.fill" accessibilityDescription:@"Folder icon"];
        }
        if (@available(macOS 10.16, *)) {
            _applyButton = iTermToolSnippetsNewButton(@"play", @"Send", self, @selector(apply:), frame);
            _addButton = iTermToolSnippetsNewButton(@"plus", @"Add", self, @selector(add:), frame);
            _removeButton = iTermToolSnippetsNewButton(@"minus", @"Remove", self, @selector(remove:), frame);
            _editButton = iTermToolSnippetsNewButton(@"square.and.pencil", @"Edit", self, @selector(edit:), frame);
            _advancedPasteButton = iTermToolSnippetsNewButton(@"rectangle.and.pencil.and.ellipsis", @"Open in Advanced Paste", self, @selector(openInAdvancedPaste:), frame);
            [self addSubview:_advancedPasteButton];
        } else {
            _applyButton = iTermToolSnippetsNewButton(nil, @"Send", self, @selector(apply:), frame);
            _addButton = iTermToolSnippetsNewButton(NSImageNameAddTemplate, nil, self, @selector(add:), frame);
            _removeButton = iTermToolSnippetsNewButton(NSImageNameRemoveTemplate, nil, self, @selector(remove:), frame);
            _editButton = iTermToolSnippetsNewButton(nil, @"✐", self, @selector(edit:), frame);
        }
        [self addSubview:_applyButton];
        [self addSubview:_addButton];
        [self addSubview:_removeButton];
        [self addSubview:_editButton];

        _standardRowHeight = [NSTableView heightForTextCellUsingFont:[NSFont it_toolbeltFont]];
        _unfilteredSnippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
        _filteredSnippets = [_unfilteredSnippets copy];
        [self buildTree];

        _outlineViewScrollView = [NSScrollView scrollViewWithOutlineViewForToolbeltWithContainer: self
                                                                                          insets:NSEdgeInsetsMake(0, 0, 0, kButtonHeight + kMargin)
                                                                                       rowHeight:[NSTableView heightForTextCellUsingFont:[NSFont it_toolbeltFont]]];
        _outlineView = _outlineViewScrollView.documentView;
        _outlineView.allowsMultipleSelection = YES;
        [_outlineView registerForDraggedTypes:@[ iTermToolSnippetsPasteboardType ]];
        _outlineView.doubleAction = @selector(doubleClickOnOutlineView:);
        [_outlineView reloadPreservingExpansionAndScroll];

        __weak __typeof(self) weakSelf = self;
        [iTermSnippetsDidChangeNotification subscribe:self
                                                block:^(iTermSnippetsDidChangeNotification * _Nonnull notification) {
            [weakSelf snippetsDidChange:notification];
        }];

        _searchField = [[iTermSearchField alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 1)];
        [_searchField sizeToFit];
        _searchField.autoresizingMask = NSViewWidthSizable;
        _searchField.frame = NSMakeRect(0, 0, frame.size.width, _searchField.frame.size.height);
        [_searchField setDelegate:self];
        [self addSubview:_searchField];
        [_searchField setArrowHandler:_outlineView];

        _help = [[NSButton alloc] initWithFrame:CGRectZero];
        [_help setBezelStyle:NSBezelStyleHelpButton];
        [_help setButtonType:NSButtonTypeMomentaryPushIn];
        [_help setBordered:YES];
        if (@available(macOS 10.16, *)) {
            _help.controlSize = NSControlSizeSmall;
        }
        [_help sizeToFit];
        _help.target = self;
        _help.action = @selector(help:);
        _help.title = @"";
        [_help setAutoresizingMask:NSViewMinXMargin];
        [self addSubview:_help];


        [self relayout];
        [self updateEnabled];
        [self registerForDraggedTypes:@[ NSPasteboardTypeString ]];
    }
    return self;
}

- (void)buildTree {
    _tree = [self makeTree];
}

- (NSArray *)makeTree {
    NSMutableArray *tagTree = [NSMutableArray array];
    [tagTree addObjectsFromArray:[_filteredSnippets mapWithBlock:^id _Nullable(iTermSnippet *snippet) {
        return [iTermSnippetItem itemWithSnippet:snippet];
    }]];

    [_filteredSnippets enumerateObjectsUsingBlock:
     ^(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        if (snippet.tags) {
            [self addTags:snippet.tags snippet:snippet toTree:tagTree];
        }
    }];
    return [self arrayByRemovingEmptyFoldersFromArray:tagTree];
}

- (NSArray *)arrayByRemovingEmptyFoldersFromArray:(NSArray *)children {
    return [children mapWithBlock:^id _Nullable(id obj) {
        if ([obj isKindOfClass:[iTermSnippetItem class]]) {
            return obj;
        }
        if ([obj isKindOfClass:[iTermSnippetFolderItem class]]) {
            iTermSnippetFolderItem *item = obj;
            NSArray *recursivelyFilteredChildren = [self arrayByRemovingEmptyFoldersFromArray:item.children];
            if (recursivelyFilteredChildren.count == 0) {
                return nil;
            }
            iTermSnippetFolderItem *modified = [[iTermSnippetFolderItem alloc] init];
            modified.path = item.path;
            modified.title = item.title;
            modified.children = recursivelyFilteredChildren;
            return modified;
        }
        assert(NO);
    }];
}

- (void)addTags:(NSArray<NSString *> *)tags snippet:(iTermSnippet *)snippet toTree:(NSMutableArray *)tree {
    [tags enumerateObjectsUsingBlock:^(NSString * _Nonnull tag, NSUInteger idx, BOOL * _Nonnull stop) {
        [self addTagComponents:[tag componentsSeparatedByString:@"/"]
                       snippet:snippet
                        toTree:tree
                       parents:@[]];
    }];
}

- (void)addTagComponents:(NSArray<NSString *> *)components
                 snippet:(iTermSnippet *)snippet
                  toTree:(NSMutableArray *)tree
                 parents:(NSArray<NSString *> *)parents {
    if (components.count == 0) {
        [tree addObject:[iTermSnippetItem itemWithSnippet:snippet]];
        return;
    }
    NSString *folderName = components[0];
    iTermSnippetFolderItem *child = [tree objectPassingTest:^BOOL(id obj, NSUInteger index, BOOL *stop) {
        return [[iTermSnippetFolderItem castFrom:obj].title isEqual:folderName];
    }];
    NSMutableArray *container;
    if (child) {
        iTermSnippetFolderItem *item = child;
        container = item.children.mutableCopy;
    } else {
        container = [NSMutableArray array];
    }
    [self addTagComponents:[components subarrayFromIndex:1]
                   snippet:snippet
                    toTree:container
                   parents:[parents arrayByAddingObject:folderName]];

    id node = [self nodeForFolderNamed:folderName path:[[parents arrayByAddingObject:folderName] componentsJoinedByString:@"/"]];
    if (!child) {
        [tree addObject:node];
        iTermSnippetFolderItem *item = node;
        item.children = container;
    } else {
        iTermSnippetFolderItem *item = child;
        item.children = container;
    }
}

- (id)nodeForFolderNamed:(NSString *)name path:(NSString *)path {
    iTermSnippetFolderItem *item = [[iTermSnippetFolderItem alloc] init];
    item.path = path;
    item.title = name;
    item.children = @[];
    return item;
}

#pragma mark - ToolbeltTool

- (void)shutdown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;

    // Search field
    NSRect searchFieldFrame = NSMakeRect(0,
                                         0,
                                         frame.size.width - kMargin - _help.frame.size.width,
                                         _searchField.frame.size.height);
    _searchField.frame = searchFieldFrame;

    CGFloat fudgeFactor = 1;
    if (@available(macOS 10.16, *)) {
        fudgeFactor = 2;
    }
    _help.frame = NSMakeRect(NSMaxX(searchFieldFrame) + kMargin, NSMinY(searchFieldFrame) + fudgeFactor, NSWidth(_help.frame), NSHeight(_help.frame));

    [_applyButton sizeToFit];
    [_applyButton setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, _applyButton.frame.size.width, kButtonHeight)];

    [_advancedPasteButton sizeToFit];
    CGFloat margin = -1;
    if (@available(macOS 10.16, *)) {
        margin = 2;
    }
    _advancedPasteButton.frame = NSMakeRect(NSMaxX(_applyButton.frame) + margin,
                                            frame.size.height - kButtonHeight,
                                            _advancedPasteButton.frame.size.width,
                                            kButtonHeight);

    CGFloat x = frame.size.width;
    for (NSButton *button in @[ _addButton, _removeButton, _editButton]) {
        [button sizeToFit];
        CGFloat width;
        if (@available(macOS 10.16, *)) {
            width = NSWidth(button.frame);
        } else {
            width = MAX(kButtonHeight, button.frame.size.width);
        }
        x -= width + margin;
        button.frame = NSMakeRect(x,
                                  frame.size.height - kButtonHeight,
                                  width,
                                  kButtonHeight);
    }

    const CGFloat searchFieldY = searchFieldFrame.size.height + kMargin;
    [_outlineViewScrollView setFrame:NSMakeRect(0, searchFieldY, frame.size.width, frame.size.height - kButtonHeight - kMargin - searchFieldY)];
    NSSize contentSize = [self contentSize];
    [_outlineView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (CGFloat)minimumHeight {
    return 87;
}

#pragma mark - NSView

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Snippets

- (BOOL)optionPressed {
    return !!([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagOption);
}

- (BOOL)shiftPressed {
    return !!([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagShift);
}

- (iTermToolSnippetsAction)preferredAction {
    if ([self optionPressed]) {
        return iTermToolSnippetsActionAdvancedPaste;
    }
    if ([self shiftPressed]) {
        return iTermToolSnippetsActionComposer;
    }
    return iTermToolSnippetsActionSend;
}

- (void)help:(id)sender {
    [_help it_showWarningWithMarkdown:iTermSnippetHelpMarkdown];
}

- (void)doubleClickOnOutlineView:(id)sender {
    [self applySelectedSnippets:[self preferredAction]];
}

- (void)apply:(id)sender {
    [self applySelectedSnippets:[self preferredAction]];
}

- (void)openInAdvancedPaste:(id)sender {
    [self applySelectedSnippets:[self shiftPressed] ? iTermToolSnippetsActionComposer : iTermToolSnippetsActionAdvancedPaste];
}

- (void)add:(id)sender {
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:nil
                                                                       completion:^(iTermSnippet * _Nullable snippet) {
        if (!snippet) {
            return;
        }
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    }];
    [self.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (void)remove:(id)sender {
    NSArray<iTermSnippet *> *snippets = [self selectedSnippets];
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] removeSnippets:snippets];
}

- (void)edit:(id)sender {
    iTermSnippet *snippet = [[self selectedSnippets] firstObject];
    if (snippet) {
        _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:snippet
                                                                           completion:^(iTermSnippet * _Nullable updatedSnippet) {
            if (!updatedSnippet) {
                return;
            }
            [[iTermSnippetsModel sharedInstance] replaceSnippet:snippet withSnippet:updatedSnippet];
        }];
        [self.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (_outlineView.window.firstResponder == _outlineView && event.keyCode == kVK_Delete) {
        [self remove:nil];
        return YES;
    }

    return [super performKeyEquivalent:event];
}

- (void)currentSessionDidChange {
    [self updateModel];
    [_outlineView reloadPreservingExpansionAndScroll];
}

#pragma mark - Private

- (void)updateModel {
    _unfilteredSnippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
    _filteredSnippets = [[iTermSnippetsModel sharedInstance] snippetsMatchingSearchQuery:_searchField.stringValue
                                                                          additionalTags:[self.toolWrapper.delegate.delegate toolbeltSnippetTags]
                                                                               tagsFound:&_haveTags];
    [self buildTree];
}

- (NSArray<iTermProfileSearchToken *> *)parseFilter:(NSString*)filter {
    NSArray *phrases = [filter componentsBySplittingProfileListQuery];
    NSMutableArray<iTermProfileSearchToken *> *tokens = [NSMutableArray array];
    for (NSString *phrase in phrases) {
        iTermProfileSearchToken *token = [[iTermProfileSearchToken alloc] initWithPhrase:phrase
                                                                               operators:@[ kTagRestrictionOperator, @"name:"]];
        [tokens addObject:token];
    }
    return tokens;
}

- (BOOL)doesSnippetWithText:(NSString *)text
                       tags:(NSArray *)tags
                matchFilter:(NSArray<iTermProfileSearchToken *> *)tokens
               nameIndexSet:(NSMutableIndexSet *)nameIndexSet
               tagIndexSets:(NSArray *)tagIndexSets {
    NSArray* nameWords = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (iTermProfileSearchToken *token in tokens) {
        // Search each word in tag until one has this token as a prefix.
        // First see if this token occurs in the title
        BOOL found = [token matchesAnyWordInNameWords:nameWords];

        if (found) {
            if (token.negated) {
                return NO;
            }
            [nameIndexSet addIndexesInRange:token.range];
        }
        // If not try each tag.
        for (int j = 0; !found && j < [tags count]; ++j) {
            // Expand the jth tag into an array of the words in the tag
            NSArray* tagWords = [[tags objectAtIndex:j] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            found = [token matchesAnyWordInTagWords:tagWords];
            if (found) {
                if (token.negated) {
                    return NO;
                }
                NSMutableIndexSet *indexSet = tagIndexSets[j];
                [indexSet addIndexesInRange:token.range];
            }
        }
        if (!token.negated && !found && text != nil) {
            // Failed to match a non-negated token. If name is nil then we don't really care about the
            // answer and we just want index sets.
            return NO;
        }
    }
    return YES;
}

- (NSSet<NSString *> *)filteredGUIDs {
    NSMutableSet<NSString *> *guids = [NSMutableSet set];
    [_filteredSnippets enumerateObjectsUsingBlock:^(iTermSnippet * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [guids addObject:obj.guid];
    }];
    return guids;
}

- (NSIndexSet *)filteredIndexSet:(NSIndexSet *)input {
    // Convert set of unfiltered indexes to a set of GUIDs.
    NSMutableSet<NSString *> *guids = [NSMutableSet set];
    [input enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        iTermSnippet *snippet = _unfilteredSnippets[i];
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

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notif {
    const BOOL hadTags = _haveTags;
    if (_haveTags || hadTags) {
        [self updateModel];
        [_outlineView reloadPreservingExpansionAndScroll];
        return;
    }
    [self updateModel];
    [self updateOutlineView];
}

- (NSInteger)filteredIndex:(NSInteger)unfilteredIndex {
    if (unfilteredIndex >= _unfilteredSnippets.count) {
        return NSNotFound;
    }
    iTermSnippet *snippet = _unfilteredSnippets[unfilteredIndex];
    return [_filteredSnippets indexOfObject:snippet];
}

- (void)updateOutlineView {
    // It would be nice to do something fancy like diff the before-and-after trees and update only
    // the necessary rows but the complexity is too great for me to do that tonight.
    [_outlineView reloadPreservingExpansionAndScroll];
}

- (void)applySelectedSnippets:(iTermToolSnippetsAction)action {
    DLog(@"%@", [NSThread callStackSymbols]);
    for (iTermSnippet *snippet in [self selectedSnippets]) {
        [self applyAction:action toSnippet:snippet];
    }
}

- (void)applyAction:(iTermToolSnippetsAction)action toSnippet:(iTermSnippet *)snippet {
    DLog(@"Create action to send snippet %@", snippet);
    iTermToolWrapper *wrapper = self.toolWrapper;
    switch (action) {
        case iTermToolSnippetsActionSend: {
            iTermAction *action = [[iTermAction alloc] initWithTitle:@"Send Snippet"
                                                              action:KEY_ACTION_SEND_SNIPPET
                                                           parameter:snippet.actionKey
                                                            escaping:snippet.escaping
                                                           applyMode:iTermActionApplyModeCurrentSession
                                                             version:snippet.version];
            [wrapper.delegate.delegate toolbeltApplyActionToCurrentSession:action];
            break;
        }
        case iTermToolSnippetsActionAdvancedPaste:
            [wrapper.delegate.delegate toolbeltOpenAdvancedPasteWithString:snippet.value
                                                                  escaping:snippet.escaping];
            break;
        case iTermToolSnippetsActionComposer:
            [wrapper.delegate.delegate toolbeltOpenComposerWithString:snippet.value
                                                             escaping:snippet.escaping];
            break;
    }
}

- (NSArray<iTermSnippet *> *)selectedSnippets {
    DLog(@"selected row indexes are %@", _outlineView.selectedRowIndexes);
    NSArray<iTermSnippet *> *snippets = _filteredSnippets;
    DLog(@"Snippets are:\n%@", snippets);
    return [[_outlineView.selectedRowIndexes it_array] mapWithBlock:^id(NSNumber *indexNumber) {
        DLog(@"Add snippet at %@", indexNumber);
        return [[iTermSnippetItem castFrom:[_outlineView itemAtRow:indexNumber.integerValue]] snippet];
    }];
}

- (NSSize)contentSize {
    NSSize size = [_outlineViewScrollView contentSize];
    size.height = _outlineView.intrinsicContentSize.height;
    return size;
}

- (NSString *)combinedStringForRow:(NSInteger)rowIndex {
    iTermSnippet *snippet = _filteredSnippets[rowIndex];
    return [self combinedStringForSnippet:snippet];
}

- (NSString *)combinedStringForSnippet:(iTermSnippet *)snippet {
    NSString *title = [snippet trimmedTitle:256];
    if (!title.length) {
        return [self valueStringForSnippet:snippet];
    }
    return [NSString stringWithFormat:@"%@ — %@", title, [snippet trimmedValue:256]];
}

- (NSString *)valueStringForRow:(NSInteger)rowIndex {
    return [self valueStringForSnippet:_filteredSnippets[rowIndex]];
}

- (NSString *)valueStringForSnippet:(iTermSnippet *)snippet {
    return [snippet trimmedValue:40];
}

- (void)update {
    [_outlineView reloadPreservingExpansionAndScroll];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[_outlineView window] firstResponder];
    if (firstResponder != _outlineView) {
        [_outlineView scrollToEndOfDocument:nil];
    }
}

- (void)fixCursor {
    [self.toolWrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)updateEnabled {
    const NSInteger numberOfRows = [[self selectedSnippets] count];
    _applyButton.enabled = numberOfRows > 0;
    _advancedPasteButton.enabled = numberOfRows == 1;
    _removeButton.enabled = numberOfRows > 0;
    _editButton.enabled = numberOfRows == 1;
}

- (NSString *)stringForRow:(NSInteger)row {
    iTermSnippet *snippet = _filteredSnippets[row];
    return [self stringForSnippet:snippet];
}

- (NSString *)stringForSnippet:(iTermSnippet *)snippet {
    if ([snippet titleEqualsValueUpToLength:40]) {
        return [self valueStringForSnippet:snippet];
    }
    return [self combinedStringForSnippet:snippet];
}

- (NSAttributedString *)attributedStringForRow:(NSInteger)row {
    iTermSnippet *snippet = _filteredSnippets[row];
    return [self attributedStringForSnippet:snippet tags:NO];
}

- (NSAttributedString *)attributedStringForSnippet:(iTermSnippet *)snippet
                                              tags:(BOOL)tags {
    NSFont *font = [NSFont it_toolbeltFont];
    NSDictionary *attributes = @{ NSFontNameAttribute: font,
                                  NSForegroundColorAttributeName: [NSColor textColor] };

    if (tags) {
        NSDictionary *attributes = @{
            NSForegroundColorAttributeName: NSColor.whiteColor,
            NSBackgroundColorAttributeName: [NSColor colorWithSRGBRed:0.97 green:0.47 blue:0.10 alpha:1.0],
            NSFontAttributeName: [font fontWithSize:round(font.pointSize * 0.8)]
        };
        if (snippet.tags.count) {
            NSArray *tagAttributedStrings = [snippet.tags flatMapWithBlock:^id _Nullable(NSString * _Nonnull tag) {
                NSAttributedString *tagString = [NSAttributedString attributedStringWithString:tag
                                                                                    attributes:attributes];
                tagString = [tagString highlightMatchesForQuery:_searchField.stringValue
                                               phraseIdentifier:[@"tag:" stringByAppendingString:tag]];
                NSAttributedString *colorSpace = [NSAttributedString attributedStringWithString:@" "
                                                                                     attributes:attributes];
                NSAttributedString *space = [NSAttributedString attributedStringWithString:@" "
                                                                                attributes:@{ NSFontAttributeName: font }];
                return @[colorSpace, tagString, colorSpace, space];
            }];
            return [NSAttributedString attributedStringWithAttributedStrings:tagAttributedStrings];
        } else {
            return [NSAttributedString attributedStringWithString:@"" attributes:attributes];
        }
    }

    if (!snippet.searchMatches) {
        NSString *string = [self stringForSnippet:snippet];
        return [NSAttributedString attributedStringWithString:string attributes:attributes];
    }

    NSString *trimmedValue = [self valueStringForSnippet:snippet];
    NSAttributedString *unhighlightedAttributedString = [NSAttributedString attributedStringWithString:trimmedValue
                                                                                            attributes:attributes];
    NSAttributedString *highlightedValueAttributedString = [unhighlightedAttributedString highlightMatchesForQuery:_searchField.stringValue
                                                                                                  phraseIdentifier:@"text:"];
    NSString *title = [snippet trimmedTitle:256];
    if ([snippet titleEqualsValueUpToLength:40] || !title.length) {
        return highlightedValueAttributedString;
    }
    NSAttributedString *emDashAttributedString = [NSAttributedString attributedStringWithString:@" — "
                                                                                     attributes:attributes];

    NSAttributedString *titleAttributedString = [NSAttributedString attributedStringWithString:title
                                                                                    attributes:attributes];
    titleAttributedString = [titleAttributedString highlightMatchesForQuery:_searchField.stringValue
                                                           phraseIdentifier:@"title:"];

    return [NSAttributedString attributedStringWithAttributedStrings:@[titleAttributedString,
                                                                       emDashAttributedString,
                                                                       highlightedValueAttributedString]];
}

- (NSAttributedString *)attributedStringForFolder:(iTermSnippetFolderItem *)folder {
    NSFont *font = [NSFont it_toolbeltFont];
    NSDictionary *attributes = @{ NSFontNameAttribute: font,
                                  NSForegroundColorAttributeName: [NSColor textColor] };
    return [NSAttributedString attributedStringWithString:folder.title attributes:attributes];
}

- (iTermTableCellView *)cellViewWithIdentifier:(NSString *)identifier centerVertically:(BOOL)centerVertically folder:(BOOL)folder {
    iTermTableCellView *cellView = [_outlineView makeViewWithIdentifier:identifier owner:self];
    NSTextField *textField;
    NSColor *iconColor =
        folder ? [NSColor colorWithSRGBRed:0.97 green:0.47 blue:0.10 alpha:1.0] : [NSColor colorWithDisplayP3Red: 94.0 / 255.0
                                                                                                           green: 159.0 / 255.0
                                                                                                            blue: 208.0 / 255.0
                                                                                                           alpha: 1];

    if (cellView == nil) {
        if (centerVertically) {
            cellView = [[iTermTwoTextFieldCell alloc] initWithIdentifier:identifier
                                                                    font:[NSFont it_toolbeltFont]
                                                                    icon:_icon
                                                                   color:iconColor];
        } else {
            if (_icon && _folderIcon) {
                cellView = [[iTermIconTableCellView alloc] initWithIcon:folder ? _folderIcon : _icon
                                                                  color:iconColor];
            } else {
                cellView = [[iTermTableCellView alloc] init];
            }
            textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
            cellView.strongTextField = textField;
            textField.font = [NSFont it_toolbeltFont];
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            textField.usesSingleLineMode = NO;
            textField.maximumNumberOfLines = 1;
            textField.cell.truncatesLastVisibleLine = YES;
            [cellView addSubview:textField];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            if (!_icon) {
                [NSLayoutConstraint activateConstraints:@[
                    [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor],
                    [textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor],
                    [textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
                ]];
            }
        }
    }
    return cellView;
}

- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item {
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    iTermSnippet *snippet = [[iTermSnippetItem castFrom:item] snippet];
    const BOOL hasTags = snippet.tags.count > 0;
    if (hasTags) {
        return [self cellViewForSnippetWithTags:snippet];
    }
    return [self regularCellViewForItem:item];
}

- (NSView *)regularCellViewForItem:(id)item {
    static NSString *const identifier = @"iTermToolSnippetsOutlineNoTags";
    iTermSnippet *snippet = [[iTermSnippetItem castFrom:item] snippet];
    iTermTableCellView *cellView = [self cellViewWithIdentifier:identifier centerVertically:NO folder:snippet == nil];
    NSTextField *textField = cellView.textField;

    if (snippet) {
        textField.attributedStringValue = [self attributedStringForSnippet:snippet tags:NO];
    } else {
        iTermSnippetFolderItem *folder = [iTermSnippetFolderItem castFrom:item];
        assert(folder);
        textField.attributedStringValue = [self attributedStringForFolder:folder];
    }
    return cellView;
}

- (NSView *)cellViewForSnippetWithTags:(iTermSnippet *)snippet {
    static NSString *const identifier = @"iTermToolSnippetsOutlineWithTags";
    iTermTableCellView *cellView = [self cellViewWithIdentifier:identifier centerVertically:YES folder:NO];
    iTermTwoTextFieldCell *cell = [iTermTwoTextFieldCell castFrom:cellView];
    cell.topTextField.attributedStringValue = [self attributedStringForSnippet:snippet tags:NO];
    cell.bottomTextField.attributedStringValue = [self attributedStringForSnippet:snippet tags:YES];
    return cellView;
}

#pragma mark - NSOutlineViewDataSource

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    iTermSnippetItem *snippetItem = [iTermSnippetItem castFrom:item];
    if (!snippetItem.snippet.tags.count) {
        return _standardRowHeight;
    }
    return _standardRowHeight * 1.8;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (!item) {
        return _tree.count;
    }
    if ([item isKindOfClass:[iTermSnippetItem class]]) {
        return 0;
    }
    iTermSnippetFolderItem *folder = [iTermSnippetFolderItem castFrom:item];
    return folder.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (!item) {
        return _tree[index];
    }
    iTermSnippetFolderItem *folder = [iTermSnippetFolderItem castFrom:item];
    return folder.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[iTermSnippetFolderItem class]];
}

#pragma mark Drag-Drop

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
    if ([item isKindOfClass:[iTermSnippetItem class]]) {
        iTermSnippet *snippet = [item snippet];
        NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
        [pbItem setPropertyList:snippet.guid forType:iTermToolSnippetsPasteboardType];
        [pbItem setString:snippet.value forType:NSPasteboardTypeString];
        return pbItem;
    } else {
        return nil;
    }
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    if ([info draggingSource] != outlineView) {
        return NSDragOperationNone;
    }
    if ([item isKindOfClass:[iTermSnippetItem class]]) {
        return NSDragOperationNone;
    }
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index {
    if (item) {
        return NO;
    }
    if (index < 0 || index > _filteredSnippets.count) {
        return NO;
    }
    NSMutableArray<NSString *> *guids = [NSMutableArray array];
    [info enumerateDraggingItemsWithOptions:0
                                    forView:outlineView
                                    classes:@[ [NSPasteboardItem class]]
                              searchOptions:@{}
                                 usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
        NSPasteboardItem *item = draggingItem.item;
        [guids addObject:[item propertyListForType:iTermToolSnippetsPasteboardType]];
    }];

    [[iTermSnippetsModel sharedInstance] moveSnippetsWithGUIDs:guids
                                                       toIndex:index];
    return YES;
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] setSnippets:snippets];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setSnippets:)
                                        object:_unfilteredSnippets];
}

#pragma mark - NSDraggingDestination

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    BOOL pasteOK = !![[sender draggingPasteboard] availableTypeFromArray:@[ NSPasteboardTypeString ]];
    if (!pasteOK) {
        return NSDragOperationNone;
    }
    return NSDragOperationGeneric;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *draggingPasteboard = [sender draggingPasteboard];
    NSArray<NSPasteboardType> *types = [draggingPasteboard types];
    if (![types containsObject:NSPasteboardTypeString]) {
        return NO;
    }
    NSString *string = [draggingPasteboard stringForType:NSPasteboardTypeString];
    if (!string.length) {
        return NO;
    }
    NSString *title = [self titleFromString:string];
    iTermSnippet *snippet = [[iTermSnippet alloc] initWithTitle:title
                                                          value:string
                                                           guid:[[NSUUID UUID] UUIDString]
                                                           tags:@[]
                                                       escaping:iTermSendTextEscapingNone
                                                        version:[iTermSnippet currentVersion]];
    [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    return YES;
}

- (NSString *)titleFromString:(NSString *)string {
    NSArray<NSString *> *parts = [string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    return [parts objectPassingTest:^BOOL(NSString *element, NSUInteger index, BOOL *stop) {
        return [[element stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] > 0;
    }] ?: @"Untitled";
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates {
    return YES;
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self updateModel];
    [_outlineView reloadPreservingExpansionAndScroll];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    const NSTextMovement movement = (NSTextMovement)[obj.userInfo[NSTextMovementUserInfoKey] integerValue];
    if (movement != NSReturnTextMovement) {
        return;
    }
    NSArray *selected = [self selectedSnippets];
    if (selected.count > 0) {
        [self applySelectedSnippets:[self preferredAction]];
    } else if (_filteredSnippets.count == 1) {
        [self applyAction:[self preferredAction] toSnippet:_filteredSnippets[0]];
    }
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    return @[];
}


@end
