#import "CPKFavoritesView.h"
#import "CPKFavorite.h"
#import "CPKSwatchView.h"
#import "NSColor+CPK.h"

static NSString *const kColorColumnIdentifier = @"color";
static NSString *const kNameColumnIdentifier = @"name";
NSString *const kCPKFavoritesDidChangeNotification = @"kCPKFavoritesDidChangeNotification";

static const CGFloat kColorColumnWidth = 25;

static NSMutableArray *gFavorites;

NSString *const kCPFavoritesUserDefaultsKey = @"kCPFavoritesUserDefaultsKey";

@interface CPKFavoritesView() <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property(nonatomic) NSTableView *tableView;
@property(nonatomic) NSTableColumn *colorColumn;
@property(nonatomic) NSTableColumn *nameColumn;
@end

@implementation CPKFavoritesView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.horizontalLineScroll = 0;
        self.horizontalPageScroll = 0;
        self.borderType = NSNoBorder;

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gFavorites = [NSMutableArray array];
            NSArray *userDefaults =
                [[NSUserDefaults standardUserDefaults] objectForKey:kCPFavoritesUserDefaultsKey];
            if (!userDefaults) {
                [gFavorites addObjectsFromArray:self.cannedFavorites];
            }
            for (NSData *data in userDefaults) {
                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
                CPKFavorite *favorite = [[CPKFavorite alloc] initWithCoder:unarchiver];
                if (favorite) {
                    [gFavorites addObject:favorite];
                }
            }
        });

        self.drawsBackground = NO;
        NSSize availableSize = [NSScrollView contentSizeForFrameSize:self.frame.size
                                             horizontalScrollerClass:nil
                                               verticalScrollerClass:self.verticalScroller.class
                                                          borderType:self.borderType
                                                         controlSize:NSRegularControlSize
                                                       scrollerStyle:NSScrollerStyleLegacy];
        self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0,
                                                                       0,
                                                                       availableSize.width,
                                                                       self.contentSize.height)];
        self.tableView.backgroundColor = [NSColor clearColor];
        self.tableView.headerView = nil;
        self.tableView.allowsMultipleSelection = YES;

        self.colorColumn = [[NSTableColumn alloc] initWithIdentifier:kColorColumnIdentifier];
        self.colorColumn.width = 25;

        self.nameColumn = [[NSTableColumn alloc] initWithIdentifier:kNameColumnIdentifier];
        [self.tableView addTableColumn:self.colorColumn];
        [self.tableView addTableColumn:self.nameColumn];

        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        [self.tableView reloadData];

        self.documentView = self.tableView;
        self.hasHorizontalScroller = NO;
        self.hasVerticalScroller = YES;
        [self.tableView sizeLastColumnToFit];

        [self.tableView registerForDraggedTypes:@[ kCPKFavoriteUTI ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(favoritesDidChange:)
                                                     name:kCPKFavoritesDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (NSArray *)cannedFavorites {
    return
    @[ [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.0 green:0.0 blue:0.0 alpha:1] name:@"Black"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.1 green:0.1 blue:0.1 alpha:1] name:@"10% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.2 green:0.2 blue:0.2 alpha:1] name:@"20% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.3 green:0.3 blue:0.3 alpha:1] name:@"30% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.4 green:0.4 blue:0.4 alpha:1] name:@"40% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.5 green:0.5 blue:0.5 alpha:1] name:@"50% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.6 green:0.6 blue:0.6 alpha:1] name:@"60% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.7 green:0.7 blue:0.7 alpha:1] name:@"70% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.8 green:0.8 blue:0.8 alpha:1] name:@"80% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:0.9 green:0.9 blue:0.9 alpha:1] name:@"90% Gray"],
       [CPKFavorite favoriteWithColor:[NSColor cpk_colorWithRed:1.0 green:1.0 blue:1.0 alpha:1] name:@"White"] ];
}

- (CPKFavorite *)favoriteForRow:(NSInteger)row {
    if (row < 0) {
        return nil;
    }
    return gFavorites[row];
}

- (NSView *)colorViewForColor:(NSColor *)color {
    // The table view wants to resize its views, so to keep it centered properly, I use a wrapper
    // view that doesn't resize its subviews.
    NSView *wrapper = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                               0,
                                                               kColorColumnWidth,
                                                               self.tableView.rowHeight - 1)];
    CPKSwatchView *view =
        [[CPKSwatchView alloc] initWithFrame:NSMakeRect(0,
                                                        1,
                                                        kColorColumnWidth,
                                                        self.tableView.rowHeight - 1)];
    wrapper.autoresizesSubviews = NO;
    [wrapper addSubview:view];
    view.color = color;
    return wrapper;
}

- (NSView *)nameViewWithValue:(NSString *)name identifier:(NSString *)identifier {
    NSTextField *textField =
        [[NSTextField alloc] initWithFrame:NSMakeRect(0,
                                                      0,
                                                      self.nameColumn.width,
                                                      self.tableView.rowHeight)];
    textField.stringValue = name ?: @"";
    textField.editable = YES;
    textField.selectable = YES;
    textField.bordered = NO;
    textField.drawsBackground = NO;
    textField.delegate = self;
    textField.identifier = identifier;

    return textField;

}

- (NSInteger)rowForFavoriteWithIdentifier:(NSString *)identifier {
    if (!identifier) {
        return -1;
    }
    for (NSInteger i = 0; i < gFavorites.count; i++) {
        if ([[gFavorites[i] identifier] isEqualToString:identifier]) {
            return i;
        }
    }
    return -1;
}

- (void)saveFavorites {
    [[NSUserDefaults standardUserDefaults] setObject:[self encodedFavorites]
                                              forKey:kCPFavoritesUserDefaultsKey];
    [self.tableView reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCPKFavoritesDidChangeNotification
                                                        object:self];
}

- (void)addFavorite:(CPKFavorite *)favorite {
    [gFavorites insertObject:favorite atIndex:0];
    [self saveFavorites];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

- (void)removeSelectedFavorites {
    NSMutableArray *identifiersToRemove = [NSMutableArray array];
    [self.tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx,
                                                                    BOOL *stop) {
        [identifiersToRemove addObject:[[gFavorites[idx] identifier] copy]];
    }];
    for (NSString *identifier in identifiersToRemove) {
        NSInteger row = [self rowForFavoriteWithIdentifier:identifier];
        if (row >= 0) {
            [gFavorites removeObjectAtIndex:row];
        }
    }
    [self saveFavorites];
    _selectionDidChangeBlock(nil);
}

- (NSArray *)encodedFavorites {
    NSMutableArray *result = [NSMutableArray array];
    for (CPKFavorite *favorite in gFavorites) {
        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [favorite encodeWithCoder:coder];
        [coder finishEncoding];

        [result addObject:data];
    }
    return result;
}

- (void)selectColor:(NSColor *)color {
    NSInteger row = [self.tableView selectedRow];
    if (row >= 0) {
        if ([[gFavorites[row] color] isApproximatelyEqualToColor:color]) {
            return;
        }
    }
    for (NSInteger i = 0; i < gFavorites.count; i++) {
        if ([[gFavorites[i] color] isApproximatelyEqualToColor:color]) {
            // Temporarily remove the block pointer to avoid notifying the client of this change,
            // since they initiated it.
            void (^saved)(NSColor *) = _selectionDidChangeBlock;
            _selectionDidChangeBlock = nil;
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i]
                        byExtendingSelection:NO];
            _selectionDidChangeBlock = saved;
            [self.tableView scrollRowToVisible:i];
            return;
        }
    }
    [self.tableView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
}

- (NSArray *)objectsForRows:(NSIndexSet *)rowIndexes {
    NSMutableArray *result = [NSMutableArray array];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [result addObject:gFavorites[idx]];
    }];
    return result;
}

#pragma mark - NSTableViewDataSource

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    CPKFavorite *favorite = [self favoriteForRow:row];
    if (tableColumn == self.colorColumn) {
        return [self colorViewForColor:favorite.color];
    } else if (tableColumn == self.nameColumn) {
        return [self nameViewWithValue:favorite.name identifier:favorite.identifier];
    } else {
        return nil;
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [gFavorites count];
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    __block NSInteger index = row;
    [info enumerateDraggingItemsWithOptions:0
                                    forView:tableView
                                    classes:@[ [CPKFavorite class] ]
                              searchOptions:@{ }
                                 usingBlock:^(NSDraggingItem *draggingItem,
                                              NSInteger idx,
                                              BOOL *stop) {
                                     CPKFavorite *favoriteToAdd = draggingItem.item;
                                     NSString *identifier = favoriteToAdd.identifier;
                                     NSInteger indexToRemove =
                                        [self rowForFavoriteWithIdentifier:identifier];
                                     BOOL shouldIncrement = YES;
                                     if (indexToRemove >= index) {
                                         ++indexToRemove;
                                     } else {
                                         shouldIncrement = NO;
                                     }
                                     [gFavorites insertObject:draggingItem.item
                                                      atIndex:index];
                                     if (shouldIncrement) {
                                         index++;
                                     }
                                     [gFavorites removeObjectAtIndex:indexToRemove];
                                 }];
    [self saveFavorites];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id <NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if (operation == NSTableViewDropOn) {
        return NSDragOperationNone;
    }

    __block BOOL shouldAccept = YES;
    [info enumerateDraggingItemsWithOptions:0
                                    forView:self.tableView
                                    classes:@[ [CPKFavorite class] ]
                              searchOptions:@{ }
                                 usingBlock:^(NSDraggingItem *draggingItem,
                                              NSInteger idx,
                                              BOOL *stop) {
                                     CPKFavorite *favorite = draggingItem.item;
                                     NSInteger row =
                                        [self rowForFavoriteWithIdentifier:favorite.identifier];
                                     if (row < 0) {
                                         // We don't accept drags from other processes yet.
                                         shouldAccept = NO;
                                         *stop = YES;
                                     }
                                 }];
    return shouldAccept ? NSDragOperationMove : NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)aTableView
    writeRowsWithIndexes:(NSIndexSet *)rowIndexes
            toPasteboard:(NSPasteboard *)pboard {
    [pboard writeObjects:[self objectsForRows:rowIndexes]];
    return YES;
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (_selectionDidChangeBlock) {
        NSInteger row = self.tableView.selectedRow;
        CPKFavorite *favorite = [self favoriteForRow:row];
        _selectionDidChangeBlock(favorite.color);
    }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    NSInteger row = [self rowForFavoriteWithIdentifier:[textField identifier]];
    if (row >= 0) {
        CPKFavorite *favorite = gFavorites[row];
        if (textField.stringValue.length != 0) {
            favorite.name = textField.stringValue;
            [self saveFavorites];
        } else {
            [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                                      columnIndexes:[NSIndexSet indexSetWithIndex:1]];
        }
    }
}

#pragma mark - Notifications

- (void)favoritesDidChange:(NSNotification *)notification {
    if (notification.object == self) {
        return;
    }
    [self.tableView reloadData];
}

@end
