//
//  ProfileTagsView.m
//  iTerm
//
//  Created by George Nachman on 1/4/14.
//
//

#import "ProfileTagsView.h"
#import "DebugLogging.h"
#import "NSTextField+iTerm.h"
#import "ProfileModel.h"

@interface ProfileTagsView ()
@property(nonatomic, readwrite, retain) NSScrollView *scrollView;
@property(nonatomic, retain) NSTableView *tableView;
@property(nonatomic, retain) NSTableColumn *tagsColumn;
@property(nonatomic, retain) NSTableHeaderView *headerView;
@property(nonatomic, retain) NSArray *cache;
@end

@implementation ProfileTagsView {
    NSFont *_font;
}

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
                                      controlSize:NSControlSizeRegular
                                    scrollerStyle:_scrollView.scrollerStyle];

        NSRect tableViewFrame = NSMakeRect(0, 0, tableViewSize.width, tableViewSize.height);
        _tableView = [[NSTableView alloc] initWithFrame:tableViewFrame];
        _tableView.allowsColumnResizing = NO;
        _tableView.allowsColumnReordering = NO;
        _tableView.allowsColumnSelection = NO;
        _tableView.allowsEmptySelection = YES;
        _tableView.allowsMultipleSelection = YES;
        _tableView.allowsTypeSelect = YES;

        _tagsColumn = [[NSTableColumn alloc] initWithIdentifier:@"tags"];
        [_tagsColumn setEditable:NO];
        [_tableView addTableColumn:_tagsColumn];

        [_scrollView setDocumentView:_tableView];
        if (@available(macOS 10.16, *)) {
            _scrollView.borderType = NSLineBorder;
        } else {
            [_scrollView setBorderType:NSBezelBorder];
        }

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

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ProfileTagIdentifier";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        if (_font) {
            result.font = _font;
        } else {
            result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        }
    }

    NSArray *tuples = [self sortedIndentedTags];
    NSString *value = tuples[row][0];
    result.stringValue = value;
    result.toolTip = value;

    return result;
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
    _font = theFont;
    NSLayoutManager* layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    [_tableView setRowHeight:[layoutManager defaultLineHeightForFont:theFont]];
}

@end
