//
//  iTermOpenQuicklyWindowController.m
//  iTerm
//
//  Created by George Nachman on 7/10/14.
//
//

#import "iTermOpenQuicklyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermLogoGenerator.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "VT100RemoteHost.h"

// It's nice for each of these to be unique so in degenerate cases (e.g., empty query) the detail
// is the same feature across the board.
static const double kSessionNameMultiplier = 2;
static const double kSessionBadgeMultiplier = 3;
static const double kCommandMultiplier = 0.8;
static const double kDirectoryMultiplier = 0.9;
static const double kHostnameMultiplier = 1.2;
static const double kUsernameMultiplier = 0.5;
static const double kProfileNameMultiplier = 1;
static const double kUserDefinedVariableMultiplier = 1;

@interface iTermOpenQuicklyTableView : NSTableView
@end

@implementation iTermOpenQuicklyTableView

- (BOOL)acceptsFirstResponder {
    return NO;
}

@end

@interface iTermOpenQuicklyRoundedCornersView : NSView
@end

@implementation iTermOpenQuicklyRoundedCornersView

- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath* path = [[[NSBezierPath alloc] init] autorelease];
    [path setLineWidth:1];
    float radius = 8;
    float x = 0.5;
    float y = radius;
    [path moveToPoint:NSMakePoint(x, y)];
    y = self.bounds.size.height - 0.5;
    [path lineToPoint:NSMakePoint(x, y - radius)];
    [path curveToPoint:NSMakePoint(x + radius, y)
         controlPoint1:NSMakePoint(x, y)
         controlPoint2:NSMakePoint(x, y)];

    x = self.bounds.size.width - 0.5;
    [path lineToPoint:NSMakePoint(x - radius, y)];
    [path curveToPoint:NSMakePoint(x, y - radius)
         controlPoint1:NSMakePoint(x, y)
         controlPoint2:NSMakePoint(x, y)];

    y = 0;
    [path lineToPoint:NSMakePoint(x, y + radius)];
    [path curveToPoint:NSMakePoint(x - radius, y)
         controlPoint1:NSMakePoint(x, y)
         controlPoint2:NSMakePoint(x, y)];

    x = 0.5;
    [path lineToPoint:NSMakePoint(x + radius, y)];
    [path curveToPoint:NSMakePoint(x, y + radius)
         controlPoint1:NSMakePoint(x, y)
         controlPoint2:NSMakePoint(x, y)];

    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    [[NSColor controlColor] set];
    [path fill];

    [[NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1] set];
    [path stroke];
}

@end
@interface iTermOpenQuicklyTableRowView : NSTableRowView
@end

@implementation iTermOpenQuicklyTableRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    NSColor *darkBlue = [NSColor colorWithCalibratedRed:89.0/255.0
                                                  green:119.0/255.0
                                                   blue:199.0/255.0
                                                  alpha:1];
    NSColor *lightBlue = [NSColor colorWithCalibratedRed:90.0/255.0
                                                   green:124.0/255.0
                                                    blue:214.0/255.0
                                                   alpha:1];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[ darkBlue, lightBlue ]];
    [gradient drawInRect:self.bounds angle:-90];
}

@end


@interface iTermOpenQuicklyTableCellView : NSTableCellView
@property (nonatomic, retain) IBOutlet NSTextField *detailTextField;
@end

@implementation iTermOpenQuicklyTableCellView

- (void)dealloc {
  [_detailTextField release];
  [super dealloc];
}

@end

@protocol iTermArrowKeyDelegate <NSObject>
- (void)keyDown:(NSEvent *)event;
@end

@interface iTermOpenQuicklyTextField : NSTextField
@property(nonatomic, assign) IBOutlet id<iTermArrowKeyDelegate> arrowHandler;
@end

@implementation iTermOpenQuicklyTextField

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
    unsigned int modflag;
    unsigned short keycode;
    modflag = [theEvent modifierFlags];
    keycode = [theEvent keyCode];

    if (![self textFieldIsFirstResponder]) {
        return NO;
    }

    const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
    // TODO(georgen): Not getting normal keycodes here, but 125 and 126 are up and down arrows.
    // This is a pretty ugly hack. Also, calling keyDown from here is probably not cool.
    BOOL handled = NO;
    if (_arrowHandler && !(mask & modflag) && (keycode == 125 || keycode == 126)) {
        static BOOL running;
        if (!running) {
            running = YES;
            [_arrowHandler keyDown:theEvent];
            running = NO;
        }
        handled = YES;
    } else {
        handled = [super performKeyEquivalent:theEvent];
    }
    return handled;
}


@end

@implementation iTermOpenQuicklyWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

@end

@interface iTermOpenQuicklyItem : NSObject
@property(nonatomic, copy) NSString *sessionId;
@property(nonatomic, copy) NSAttributedString *title;
@property(nonatomic, retain) NSAttributedString *detail;
@property(nonatomic, assign) double score;
@property(nonatomic, retain) iTermOpenQuicklyTableCellView *view;
@property(nonatomic, retain) NSColor *textColor;
@property(nonatomic, retain) NSColor *cursorColor;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *tabColor;
@end

@implementation iTermOpenQuicklyItem

- (void)dealloc {
    [_sessionId release];
    [_title release];
    [_detail release];
    [_view release];
    [_textColor release];
    [_backgroundColor release];
    [_tabColor release];
    [_cursorColor release];
    [super dealloc];
}

@end

@interface iTermOpenQuicklyWindowController () <
    iTermArrowKeyDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSWindowDelegate>

@property(nonatomic, retain) NSMutableArray *items;

@end

@implementation iTermOpenQuicklyWindowController {
    IBOutlet iTermOpenQuicklyTextField *_textField;
    IBOutlet NSTableView *_table;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super initWithWindowNibName:@"iTermOpenQuicklyWindowController"];
    if (self) {
        // Placeholder in case there's something to do
    }
    return self;
}

- (void)awakeFromNib {
    [_table setDoubleAction:@selector(doubleClick:)];
    [self.window setOpaque:NO];
}

- (void)dealloc {
    [_items release];
    [super dealloc];
}

- (void)presentWindow {
    [_items removeAllObjects];
    [self update];
    NSRect frame = [self frame];
    [self.window setFrame:frame display:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (double)qualityOfMatchBetweenQuery:(unichar *)query
                           andString:(NSString *)documentString
                            indexSet:(NSMutableIndexSet *)indexSet {
    // Returns 1 if query is a subsequence of document and 0 if not.
    // Returns 2 if query is a prefix of document.
    unichar *document = (unichar *)malloc(documentString.length * sizeof(unichar) + 1);
    [documentString getCharacters:document];
    document[documentString.length] = 0;
    int q = 0;
    int d = 0;
    while (query[q] && document[d]) {
        if (document[d] == query[q]) {
            [indexSet addIndex:d];
            ++q;
        }
        ++d;
    }
    double score;
    if (query[q]) {
        score = 0;
    } else if (q == d) {
        // Is a prefix
        score = 2;
    } else {
        score = 1;
    }
    free(document);
    return score;
}

- (double)scoreForQuery:(unichar *)query
              documents:(NSArray *)documents
             multiplier:(double)multipler
                   name:(NSString *)name
               features:(NSMutableArray *)features
                  limit:(double)limit {
    if (multipler == 0) {
        // Feature is disabled. In the future, we might let users tweak multipliers.
        return 0;
    }
    double score = 0;
    double highestValue = 0;
    NSString *bestFeature = nil;
    NSIndexSet *bestIndexSet = nil;
    int n = documents.count;
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (NSString *document in documents) {
        [indexSet removeAllIndexes];
        double value = [self qualityOfMatchBetweenQuery:query
                                              andString:[document lowercaseString]
                                               indexSet:indexSet];

        // Discount older documents (which appear at the beginning of the list)
        value /= n;
        n--;

        if (value > highestValue) {
            highestValue = value;
            bestFeature = document;
            bestIndexSet = [[indexSet copy] autorelease];
        }
        score += value * multipler;
        if (score > limit) {
            break;
        }
    }

    if (bestFeature && features) {
        NSString *prefix;
        if (name) {
            prefix = [NSString stringWithFormat:@"%@: ", name];
        } else {
            prefix = @"";
        }
        NSMutableAttributedString *theString =
            [[[NSMutableAttributedString alloc] initWithString:prefix] autorelease];
        [theString appendAttributedString:[self attributedStringFromString:bestFeature
                                                     byHighlightingIndices:bestIndexSet]];
        [features addObject:@[ theString, @(score) ]];
    }

    return MIN(limit, score);
}

- (NSAttributedString *)attributedStringFromString:(NSString *)source
                             byHighlightingIndices:(NSIndexSet *)indexSet {
    NSMutableAttributedString *attributedString =
        [[[NSMutableAttributedString alloc] initWithString:source attributes:@{}] autorelease];
    NSDictionary *highlight = @{ NSBackgroundColorAttributeName: [[NSColor yellowColor] colorWithAlphaComponent:0.4] };
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [attributedString setAttributes:highlight range:NSMakeRange(idx, 1)];
    }];
    return attributedString;
}

- (NSArray *)hostnamesInHosts:(NSArray *)hosts {
    NSMutableArray *names = [NSMutableArray array];
    for (VT100RemoteHost *host in hosts) {
        [names addObject:host.hostname];
    }
    return names;
}

- (NSArray *)usernamesInHosts:(NSArray *)hosts {
    NSMutableArray *names = [NSMutableArray array];
    for (VT100RemoteHost *host in hosts) {
        [names addObject:host.username];
    }
    return names;
}

- (double)scoreForSession:(PTYSession *)session
                    query:(unichar *)query
                   length:(int)length
                 features:(NSMutableArray *)features
           attributedName:(NSMutableAttributedString *)attributedName {
    double score = 0;
    double maxScorePerFeature = 2 + length / 4;
    if (session.name) {
        NSMutableArray *nameFeature = [NSMutableArray array];
        score += [self scoreForQuery:query
                           documents:@[ session.name ]
                          multiplier:kSessionNameMultiplier
                                name:nil
                            features:nameFeature
                               limit:maxScorePerFeature];
        if (nameFeature.count) {
            [attributedName appendAttributedString:nameFeature[0][0]];
        }
    }

    if (session.badgeLabel) {
        score += [self scoreForQuery:query
                           documents:@[ session.badgeLabel ]
                          multiplier:kSessionBadgeMultiplier
                                name:@"Badge"
                            features:features
                               limit:maxScorePerFeature];
    }

    score += [self scoreForQuery:query
                       documents:session.commands
                      multiplier:kCommandMultiplier
                            name:@"Command"
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:session.directories
                      multiplier:kDirectoryMultiplier
                            name:@"Directory"
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:[self hostnamesInHosts:session.hosts]
                      multiplier:kHostnameMultiplier
                            name:@"Host"
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:[self usernamesInHosts:session.hosts]
                      multiplier:kUsernameMultiplier
                            name:@"User"
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:@[ session.profile[KEY_NAME] ?: @"" ]
                      multiplier:kProfileNameMultiplier
                            name:@"Profile"
                        features:features
                           limit:maxScorePerFeature];

    for (NSString *var in session.variables) {
        if ([var hasPrefix:@"user."]) {
            score += [self scoreForQuery:query
                               documents:@[ session.variables[var] ]
                              multiplier:kUserDefinedVariableMultiplier
                                    name:[var substringFromIndex:[@"user." length]]
                                features:features
                                   limit:maxScorePerFeature];
        }
    }

    // TODO: add a bonus for:
    // Doing lots of typing in a session
    // Being newly created
    // Recency of use

    return score;
}

- (NSAttributedString *)detailForSession:(PTYSession *)session features:(NSArray *)features {
    NSArray *sorted = [features sortedArrayUsingComparator:^NSComparisonResult(NSArray *tuple1, NSArray *tuple2) {
        NSNumber *score1 = tuple1[1];
        NSNumber *score2 = tuple2[1];
        return [score1 compare:score2];
    }];
    return [sorted lastObject][0];
}

- (NSArray *)sessions {
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    // sessions and scores are parallel.
    NSMutableArray *sessions = [NSMutableArray array];
    for (PseudoTerminal *term in terminals) {
        [sessions addObjectsFromArray:term.sessions];
    }
    return sessions;
}

- (void)update {
    NSArray *sessions = [self sessions];

    NSString *queryString = [_textField.stringValue lowercaseString];
    unichar *query = (unichar *)malloc(queryString.length * sizeof(unichar) + 1);
    [queryString getCharacters:query];
    query[queryString.length] = 0;

    NSMutableArray *items = [NSMutableArray array];
    for (PTYSession *session in sessions) {
        NSMutableArray *features = [NSMutableArray array];
        iTermOpenQuicklyItem *item = [[[iTermOpenQuicklyItem alloc] init] autorelease];
        item.textColor = session.foregroundColor;
        item.backgroundColor = session.backgroundColor;
        item.tabColor = session.tabColor;
        item.cursorColor = session.cursorColor;

        NSMutableAttributedString *attributedName = [[[NSMutableAttributedString alloc] init] autorelease];
        item.score = [self scoreForSession:session
                                     query:query
                                    length:queryString.length
                                  features:features
                            attributedName:attributedName];
        if (item.score > 0) {
            item.detail = [self detailForSession:session features:features];
            item.title =
                [attributedName length] ? attributedName
                                        : [[[NSAttributedString alloc] initWithString:session.name
                                                                           attributes:@{}] autorelease];
            item.sessionId = session.uniqueID;
            [items addObject:item];
        }
    }

    // Sort from highest to lowest score.
    [items sortUsingComparator:^NSComparisonResult(iTermOpenQuicklyItem *obj1,
                                                   iTermOpenQuicklyItem *obj2) {
        return [@(obj2.score) compare:@(obj1.score)];
    }];

    // Replace self.items with new items.
    self.items = items;
    [_table reloadData];

    free(query);
    [self.window setFrame:[self frame] display:YES animate:YES];
    if (_items.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self tableViewSelectionDidChange:nil];
    }
}

- (NSRect)frame {
    NSScreen *screen = [[NSApp keyWindow] screen];
    if (!screen) {
        screen = [NSScreen mainScreen];
    }
    static const CGFloat kMarginAboveField = 6;
    static const CGFloat kMarginBelowField = 6;
    static const CGFloat kMarginAboveWindow = 170;
    CGFloat maxHeight = screen.frame.size.height - kMarginAboveWindow * 2;
    CGFloat nonTableSpace = kMarginAboveField + _textField.frame.size.height + kMarginBelowField;
    int numberOfVisibleRowsDesired = MIN(_items.count,
                                         (maxHeight - nonTableSpace) / (_table.rowHeight + _table.intercellSpacing.height));
    NSRect frame = self.window.frame;
    NSSize contentSize = frame.size;
    contentSize.height = nonTableSpace + (_table.rowHeight + _table.intercellSpacing.height) * numberOfVisibleRowsDesired;

    if (numberOfVisibleRowsDesired) {
        frame.size.height = [NSScrollView frameSizeForContentSize:contentSize
                                            hasHorizontalScroller:NO
                                              hasVerticalScroller:YES
                                                       borderType:NSBezelBorder].height;
    } else {
        frame.size.height = contentSize.height;
    }

    frame.origin.x = floor((screen.frame.size.width - frame.size.width) / 2);
    frame.origin.y = screen.frame.origin.y + screen.frame.size.height - kMarginAboveWindow - frame.size.height;
    return frame;
}

- (IBAction)close:(id)sender {
    [self.window close];
}

- (void)openSelectedRow {
    NSInteger row = [_table selectedRow];

    if (row >= 0) {
        iTermOpenQuicklyItem *item = _items[row];
        NSString *sessionId = item.sessionId;
        for (PTYSession *session in [self sessions]) {
            if ([session.uniqueID isEqualTo:sessionId]) {
                NSWindowController<iTermWindowController> *term = session.tab.realParentWindow;
                [term makeSessionActive:session];
                break;
            }
        }
    }

    [self close:nil];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    iTermOpenQuicklyTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    iTermOpenQuicklyItem *item = _items[row];
    item.view = result;
    iTermLogoGenerator *logoGenerator = [[iTermLogoGenerator alloc] init];
    logoGenerator.backgroundColor = item.backgroundColor;
    logoGenerator.textColor = item.textColor;
    logoGenerator.tabColor = item.tabColor;
    logoGenerator.cursorColor = item.cursorColor;
    result.imageView.image = [logoGenerator generatedImage];
    result.textField.attributedStringValue =
        item.title ?: [[[NSAttributedString alloc] initWithString:@"Untitled" attributes:@{}] autorelease];
    if (item.detail) {
        result.detailTextField.attributedStringValue = item.detail;
    } else {
        result.detailTextField.stringValue = @"";
    }
    NSColor *color;
    if (row == tableView.selectedRow) {
        color = [NSColor whiteColor];
    } else {
        color = [NSColor blackColor];
    }
    result.textField.textColor = color;
    result.detailTextField.textColor = color;
    return result;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[iTermOpenQuicklyTableRowView alloc] init];
}

- (void)tableViewSelectionIsChanging:(NSNotification *)notification {
    NSInteger row = [_table selectedRow];
    if (row >= 0) {
        iTermOpenQuicklyItem *item = _items[row];
        item.view.textField.textColor = [NSColor blackColor];
        item.view.detailTextField.textColor = [NSColor blackColor];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [_table selectedRow];
    for (int i = 0; i < _items.count; i++) {
        iTermOpenQuicklyItem *item = _items[i];
        if (i == row) {
            item.view.textField.textColor = [NSColor whiteColor];
            item.view.detailTextField.textColor = [NSColor whiteColor];
        } else {
            item.view.textField.textColor = [NSColor blackColor];
            item.view.detailTextField.textColor = [NSColor blackColor];
        }
    }
}

- (void)doubleClick:(id)sender {
    [self openSelectedRow];
}

#pragma mark - NSWindowDelegate

- (void)windowDidResignKey:(NSNotification *)notification {
    [self.window close];
}

#pragma mark - NSControlDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    [self update];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    int move = [[[notification userInfo] objectForKey:@"NSTextMovement"] intValue];

    switch (move) {
        case NSReturnTextMovement:
            [self openSelectedRow];
            break;
        default:
            break;
    }
}

#pragma mark - iTermArrowKeyDelegate

- (void)keyDown:(NSEvent *)theEvent {
    static BOOL running;
    if (!running) {
        running = YES;
        [_table keyDown:theEvent];
        running = NO;
    }
}

@end
