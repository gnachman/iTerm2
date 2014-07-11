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
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "VT100RemoteHost.h"

static const double kSessionNameMultiplier = 1;
static const double kSessionBadgeMultiplier = 1;
static const double kCommandMultiplier = 1;
static const double kDirectoryMultiplier = 1;
static const double kHostnameMultiplier = 1;
static const double kUsernameMultiplier = 1;
static const double kProfileNameMultiplier = 1;

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

@interface iTermOpenQuicklyItem : NSObject <NSCopying>
@property(nonatomic, copy) NSString *sessionId;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, assign) double score;
@end

@implementation iTermOpenQuicklyItem

- (void)dealloc {
    [_sessionId release];
    [_title release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
    iTermOpenQuicklyItem *theCopy = [[iTermOpenQuicklyItem alloc] init];
    theCopy.sessionId = self.sessionId;
    theCopy.title = self.title;
    theCopy.score = self.score;
    return theCopy;
}

@end

@interface iTermOpenQuicklyWindowController () <iTermArrowKeyDelegate, NSTableViewDataSource, NSWindowDelegate>

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

- (double)qualityOfMatchBetweenQuery:(unichar *)query andString:(NSString *)documentString {
    // Returns 1 if query is a subsequence of document and 0 if not.
    // Returns 2 if query is a prefix of document.
    unichar *document = (unichar *)malloc(documentString.length * sizeof(unichar) + 1);
    [documentString getCharacters:document];
    document[documentString.length] = 0;
    int q = 0;
    int d = 0;
    while (query[q] && document[d]) {
        if (document[d] == query[q]) {
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
               features:(NSMutableArray *)features
                  limit:(double)limit {
    double score = 0;
    double highestValue = 0;
    NSString *bestFeature = nil;
    int n = documents.count;
    for (NSString *document in documents) {
        double value = [self qualityOfMatchBetweenQuery:query andString:document];

        // Discount older documents (which appear at the beginning of the list)
        value /= n;
        n--;

        if (value > highestValue) {
            highestValue = value;
            bestFeature = document;
        }
        score += value * multipler;
        if (score > limit) {
            break;
        }
    }

    if (bestFeature) {
        [features addObject:bestFeature];
    }

    return MIN(limit, score);
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
                 features:(NSMutableArray *)features {
    double score = 0;
    double maxScorePerFeature = 2 + length / 4;

    if (session.name) {
        score += [self scoreForQuery:query
                           documents:@[ session.name ]
                          multiplier:kSessionNameMultiplier
                            features:features
                               limit:maxScorePerFeature];
    }

    if (session.badgeLabel) {
        score += [self scoreForQuery:query
                           documents:@[ session.badgeLabel ]
                          multiplier:kSessionBadgeMultiplier
                            features:features
                               limit:maxScorePerFeature];
    }

    score += [self scoreForQuery:query
                       documents:session.commands
                      multiplier:kCommandMultiplier
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:session.directories
                      multiplier:kDirectoryMultiplier
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:[self hostnamesInHosts:session.hosts]
                      multiplier:kHostnameMultiplier
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:[self usernamesInHosts:session.hosts]
                      multiplier:kUsernameMultiplier
                        features:features
                           limit:maxScorePerFeature];

    score += [self scoreForQuery:query
                       documents:@[ session.profile[KEY_NAME] ?: @"" ]
                      multiplier:kProfileNameMultiplier
                        features:features
                           limit:maxScorePerFeature];

    // TODO: add a bonus for:
    // Doing lots of typing in a session
    // Being newly created
    // Recency of use

    return score;
}

- (NSString *)titleForSession:(PTYSession *)session features:(NSArray *)features {
    // TODO: Make this make some kind of sense
    return [features componentsJoinedByString:@" "];
}

- (void)update {
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    // sessions and scores are parallel.
    NSMutableArray *sessions = [NSMutableArray array];
    for (PseudoTerminal *term in terminals) {
        [sessions addObjectsFromArray:term.sessions];
    }

    NSString *queryString = _textField.stringValue;
    unichar *query = (unichar *)malloc(queryString.length * sizeof(unichar) + 1);
    [queryString getCharacters:query];
    query[queryString.length] = 0;

    NSMutableArray *items = [NSMutableArray array];
    for (PTYSession *session in sessions) {
        NSMutableArray *features = [NSMutableArray array];
        iTermOpenQuicklyItem *item = [[[iTermOpenQuicklyItem alloc] init] autorelease];
        item.score = [self scoreForSession:session
                                     query:query
                                    length:queryString.length
                                  features:features];
        if (item.score > 0) {
            item.title = [self titleForSession:session features:features];
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
                                         (maxHeight - nonTableSpace) / _table.rowHeight);

    NSRect frame = self.window.frame;
    frame.size.height = nonTableSpace + _table.rowHeight * numberOfVisibleRowsDesired;
    frame.origin.x = floor((screen.frame.size.width - frame.size.width) / 2);
    frame.origin.y = screen.frame.origin.y + screen.frame.size.height - kMarginAboveWindow - frame.size.height;
    return frame;
}

- (IBAction)close:(id)sender {
    [self.window close];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _items.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [_items[row] title];
}

#pragma mark - NSWindowDelegate

- (void)windowDidResignKey:(NSNotification *)notification {
    [self.window close];
}

#pragma mark - NSControlDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    [self update];
}

#pragma mark - iTermArrowKeyDelegate

- (void)keyDown:(NSEvent *)theEvent {
    [_table keyDown:theEvent];
}

@end
