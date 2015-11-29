//
//  ProfileTagsView.m
//  iTerm
//
//  Created by George Nachman on 1/4/14.
//
//

#import "ProfileTagsView.h"
#import "DebugLogging.h"
#import "ProfileModel.h"

static const CGFloat kRowHeight = 21;

@interface ProfileTagsView ()
@property(nonatomic, retain) NSScrollView *scrollView;
@property(nonatomic, retain) NSTableView *tableView;
@property(nonatomic, retain) NSTableColumn *tagsColumn;
@property(nonatomic, retain) NSTableHeaderView *headerView;
@property(nonatomic, retain) NSArray *cache;
@end

@implementation ProfileTagsView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.hasHorizontalScroller = NO;
        [self addSubview:_scrollView];
        
        NSSize tableViewSize =
            [NSScrollView contentSizeForFrameSize:_scrollView.frame.size
                          horizontalScrollerClass:nil
                            verticalScrollerClass:[_scrollView.verticalScroller class]
                                       borderType:_scrollView.borderType
                                      controlSize:NSRegularControlSize
                                    scrollerStyle:_scrollView.scrollerStyle];

        NSRect tableViewFrame = NSMakeRect(0, 0, tableViewSize.width, tableViewSize.height);
        _tableView = [[NSTableView alloc] initWithFrame:tableViewFrame];
        _tableView.rowHeight = kRowHeight;
        _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
        _tableView.allowsColumnResizing = NO;
        _tableView.allowsColumnReordering = NO;
        _tableView.allowsColumnSelection = NO;
        _tableView.allowsEmptySelection = YES;
        _tableView.allowsMultipleSelection = YES;
        _tableView.allowsTypeSelect = YES;
        _tableView.backgroundColor = [NSColor whiteColor];

        _tagsColumn = [[NSTableColumn alloc] initWithIdentifier:@"tags"];
        [_tagsColumn setEditable:NO];
        [_tableView addTableColumn:_tagsColumn];

        [_scrollView setDocumentView:_tableView];
        [_scrollView setBorderType:NSBezelBorder];

        _tableView.delegate = self;
        _tableView.dataSource = self;

        _headerView = [[NSTableHeaderView alloc] init];
        _tableView.headerView = _headerView;
        [_tagsColumn.headerCell setStringValue:@"Tag Name"];
        _tagsColumn.width = [_tagsColumn.headerCell cellSize].width;
        
        [_tableView sizeLastColumnToFit];
        _scrollView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAddressBook:)
                                                     name:kReloadAddressBookNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_scrollView release];
    [_tableView release];
    [_tagsColumn release];
    [_headerView release];
    [_cache release];
    [super dealloc];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [_delegate profileTagsViewSelectionDidChange:self];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [[self sortedIndentedTags] count];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    NSArray *tuples = [self sortedIndentedTags];
    return tuples[rowIndex][0];
}

#pragma mark - Notifications

- (void)reloadAddressBook:(NSNotification *)notification {
    DLog(@"Doing reload data on tags view");
    self.cache = nil;
    [_tableView reloadData];
}

#pragma mark - APIs

- (NSArray *)selectedTags {
    NSMutableArray *tags = [NSMutableArray array];
    NSIndexSet *set = [_tableView selectedRowIndexes];
    NSArray *tuples = [self sortedIndentedTags];
    NSUInteger currentIndex = [set firstIndex];
    while (currentIndex != NSNotFound) {
        [tags addObject:tuples[currentIndex][1]];
        currentIndex = [set indexGreaterThanIndex:currentIndex];
    }
    return tags;
}

#pragma mark - Private

- (int)numberOfPartsMatchedBetween:(NSArray *)a and:(NSArray *)b {
    int n = 0;
    for (int i = 0; i < a.count && i < b.count; i++) {
        if ([a[i] isEqualToString:b[i]]) {
            n++;
        } else {
            break;
        }
    }
    return n;
}

- (NSString *)stringForIndentLevel:(int)level {
    NSMutableString *string = [NSMutableString string];
    unichar chars[] = { 0xa0, 0xa0 };
    NSString *space = [NSString stringWithCharacters:chars length:sizeof(chars) / sizeof(*chars)];
    
    for (int i = 0; i < level; i++) {
        [string appendString:space];
    }
    return string;
}

- (NSArray *)sortedIndentedTags {
    if (!_cache) {
        NSMutableArray *result = [NSMutableArray array];
        NSArray *tags = [[[ProfileModel sharedInstance] allTags] sortedArrayUsingSelector:@selector(compare:)];
        NSArray *previousParts = [NSMutableArray array];
        for (int i = 0; i < tags.count; i++) {
            NSString *tagName = tags[i];
            NSArray *currentParts = [tagName componentsSeparatedByString:@"/"];
            int numPartsMatched = [self numberOfPartsMatchedBetween:previousParts and:currentParts];
            while (numPartsMatched < currentParts.count) {
                NSString *key = [NSString stringWithFormat:@"%@%@",
                                 [self stringForIndentLevel:numPartsMatched],
                                 currentParts[numPartsMatched]];
                NSString *value = [[currentParts subarrayWithRange:NSMakeRange(0, numPartsMatched + 1)] componentsJoinedByString:@"/"];
                [result addObject:@[ key, value ]];
                ++numPartsMatched;
            }
            previousParts = currentParts;
        }
        self.cache = result;
    }

    return _cache;
}

- (void)setFont:(NSFont *)theFont {
    for (NSTableColumn *col in [_tableView tableColumns]) {
        [[col dataCell] setFont:theFont];
    }
    NSLayoutManager* layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    [_tableView setRowHeight:[layoutManager defaultLineHeightForFont:theFont]];
}

@end
