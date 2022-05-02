//
//  iTermGlobalSearchWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import "iTermGlobalSearchWindowController.h"

#import "FindContext.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermController.h"
#import "iTermFocusReportingTextField.h"
#import "iTermGlobalSearchEngine.h"
#import "iTermGlobalSearchOutlineView.h"
#import "iTermGlobalSearchResult.h"
#import "iTermSearchFieldCell.h"
#import "iTermUserDefaults.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "SearchResult.h"
#import "VT100Screen.h"


@interface iTermGlobalSearchWindowController ()<
    iTermFocusReportingSearchFieldDelegate,
    NSOutlineViewDelegate,
    NSOutlineViewDataSource,
    NSWindowDelegate>
@end

@implementation iTermGlobalSearchWindowController {
    iTermGlobalSearchEngine *_engine;
    NSMutableDictionary<NSString *, NSMutableArray<iTermGlobalSearchResult *> *> *_results;
    IBOutlet iTermFocusReportingSearchField *_searchField;
    IBOutlet NSPopUpButton *_findType;
    IBOutlet NSOutlineView *_outlineView;
    IBOutlet NSPanel *_panel;
    BOOL _ignoreClick;

    // Fades out the progress indicator.
    NSTimer *_animationTimer;
}

- (instancetype)init {
    return [super initWithWindowNibName:@"iTermGlobalSearch"];
}

- (void)windowDidLoad {
    self.window.delegate = self;
    self.window.level = NSFloatingWindowLevel;
    [_outlineView expandItem:nil expandChildren:YES];
    _panel.becomesKeyOnlyIfNeeded = YES;
    [_findType selectItemWithTag:[iTermUserDefaults globalSearchMode]];
    _outlineView.target = self;
    _outlineView.action = @selector(didClick:);
}

- (NSArray<PTYSession *> *)sessions {
    return [[[iTermController sharedInstance] terminals] flatMapWithBlock:^NSArray *(PseudoTerminal *terminal) {
        return [terminal.tabs flatMapWithBlock:^NSArray *(PTYTab *tab) {
            return tab.sessions;
        }];
    }];
}

- (void)setFraction:(double)progress {
    iTermSearchFieldCell *cell = [iTermSearchFieldCell castFrom:_searchField.cell];
    if (round(progress * 100) != round(cell.fraction * 100)) {
        [_searchField setNeedsDisplay:YES];
    }

    [cell setFraction:progress];
    if (cell.needsAnimation && !_animationTimer) {
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1/60.0
                                                           target:self
                                                         selector:@selector(redrawSearchField:)
                                                         userInfo:nil
                                                          repeats:YES];
    }
}

- (void)redrawSearchField:(NSTimer *)timer {
    iTermSearchFieldCell *cell = [iTermSearchFieldCell castFrom:_searchField.cell];
    [cell willAnimate];
    if (!cell.needsAnimation) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    [_searchField setNeedsDisplay:YES];
}

- (void)addResults:(NSArray<iTermGlobalSearchResult *> *)results
        forSession:(PTYSession *)session
          progress:(double)progress {
    if (!session) {
        // Finished searching.
        [self setFraction:1];
        return;
    }
    [self setFraction:progress];
    if (!results.count) {
        return;
    }
    if (!_results) {
        _results = [NSMutableDictionary dictionary];
    }
    NSMutableArray<iTermGlobalSearchResult *> *sessionResults = _results[session.guid];
    [_outlineView beginUpdates];
    BOOL isNew = (sessionResults == nil);
    if (!sessionResults) {
        sessionResults = [NSMutableArray array];
        _results[(NSString * _Nonnull)session.guid] = sessionResults;
    }
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(sessionResults.count, results.count)];
    [sessionResults addObjectsFromArray:results];
    if (isNew) {
        const NSUInteger i = [self.sortedNonEmptyResultSessionGUIDs indexOfObject:session.guid];
        if (i != NSNotFound) {
            [_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:i]
                                      inParent:nil
                                 withAnimation:NO];
        }
    }
    [_outlineView insertItemsAtIndexes:indexes
                              inParent:session.guid
                         withAnimation:NO];
    [_outlineView expandItem:session.guid expandChildren:YES];
    [_outlineView endUpdates];
}

static double Square(double n) {
    return n * n;
}

static double EuclideanDistance(NSPoint p1, NSPoint p2) {
    return sqrt(Square(p1.x - p2.x) + Square(p1.y - p2.y));
}

- (void)revealSelection {
    [_searchField setNeedsDisplay:YES];
    id item = [_outlineView itemAtRow:_outlineView.selectedRow];
    NSString *guid = [NSString castFrom:item];
    if (guid) {
        PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:guid];
        [session reveal];
        return;
    }
    iTermGlobalSearchResult *result = [iTermGlobalSearchResult castFrom:item];
    if (!result) {
        return;
    }

    [result.session reveal];
    if (result.isExternal) {
        [result.session.externalSearchResultsController selectExternalSearchResult:result.result.externalResult
                                                                          multiple:NO
                                                                            scroll:YES];
    } else {
        const VT100GridCoordRange coordRange = [result internalCoordRange];
        [result.session.textview selectCoordRange:coordRange];
        [result.session.textview scrollToSelection];
        [result highlightLines];
        [self movePanelAwayFromResultInRange:coordRange session:result.session];
    }
}

- (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange session:(PTYSession *)session {
    NSRect (^screenRect)(VT100GridCoord) = ^NSRect(VT100GridCoord coord) {
        const NSRect viewRect = [session.textview frameForCoord:coord];
        const NSRect windowRect = [session.textview convertRect:viewRect toView:nil];
        return [session.textview.window convertRectToScreen:windowRect];
    };
    const NSRect firstRect = screenRect(coordRange.start);
    const NSRect lastRect = screenRect(coordRange.end);
    return NSUnionRect(firstRect, lastRect);
}

- (void)movePanelAwayFromResultInRange:(VT100GridCoordRange)coordRange session:(PTYSession *)session {
    const NSRect hull = [self rectForCoordRange:coordRange session:session];
    const NSRect windowRect = _panel.frame;
    if (!NSIntersectsRect(windowRect, hull)) {
        return;
    }

    // Move it above, below, left, or right. Pick the option where the least amount of the
    // window falls off the screen.
    NSRect candidates[] = {
        NSMakeRect(NSMinX(hull) - NSWidth(windowRect),  // left
                   NSMinY(windowRect),
                   NSWidth(windowRect),
                   NSHeight(windowRect)),
        NSMakeRect(NSMaxX(hull),  // right
                   NSMinY(windowRect),
                   NSWidth(windowRect),
                   NSHeight(windowRect)),
        NSMakeRect(NSMinX(windowRect),  // down
                   NSMaxY(hull),
                   NSWidth(windowRect),
                   NSHeight(windowRect)),
        NSMakeRect(NSMinX(windowRect),  // up
                   NSMinY(hull) - NSHeight(windowRect),
                   NSWidth(windowRect),
                   NSHeight(windowRect)),
    };
    const NSRect screenFrame = _panel.screen.visibleFrame;
    const CGFloat totalArea = NSWidth(_panel.frame) * NSHeight(_panel.frame);
    CGFloat bestAreaOffScreen = INFINITY;
    CGFloat bestDistance = INFINITY;
    int bestIndex = -1;
    for (int i = 0; i < sizeof(candidates) / sizeof(*candidates); i++) {
        const NSRect onScreenRect = NSIntersectionRect(candidates[i], screenFrame);
        const CGFloat areaOffScreen = totalArea - (onScreenRect.size.width * onScreenRect.size.height);
        const CGFloat distance = EuclideanDistance(_panel.frame.origin, candidates[i].origin);
        if (bestAreaOffScreen > areaOffScreen) {
            bestAreaOffScreen = areaOffScreen;
            bestDistance = distance;
            bestIndex = i;
        } else if (bestAreaOffScreen == areaOffScreen && bestDistance > distance) {
            bestDistance = distance;
            bestIndex = i;
        }
    }
    if (bestIndex != -1) {
        [_panel setFrame:candidates[bestIndex] display:YES animate:YES];
    }
}

- (void)activate {
    [self.window makeKeyAndOrderFront:nil];
    [_searchField.window makeFirstResponder:_searchField];
}

- (IBAction)closeCurrentSession:(id)sender {
    [self close];
}

- (void)closeWindow:(id)sender {
    [self close];
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self.window makeFirstResponder:_searchField];
}

#pragma mark - Actions

- (IBAction)modeDidChange:(id)sender {
    [self search:nil];
    [iTermUserDefaults setGlobalSearchMode:_findType.selectedTag];
}

- (iTermFindMode)mode {
    return _findType.selectedTag;
}

- (IBAction)search:(id)sender {
    [_engine stop];
    _results = [NSMutableDictionary dictionary];
    [self setFraction:0];
    [_outlineView reloadData];
    if (_searchField.stringValue.length == 0) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    _engine = [[iTermGlobalSearchEngine alloc] initWithQuery:_searchField.stringValue
                                                    sessions:self.sessions
                                                        mode:self.mode
                                                     handler:^(PTYSession *session,
                                                               NSArray<iTermGlobalSearchResult *> *results,
                                                               double progress) {
        [weakSelf addResults:results forSession:session progress:progress];
    }];
}

- (void)didClick:(id)sender {
    if (_ignoreClick) {
        return;
    }
    [self revealSelection];
}

#pragma mark - iTermFocusReportingSearchFieldDelegate

- (void)focusReportingSearchFieldWillBecomeFirstResponder:(iTermFocusReportingSearchField *)sender {
}

- (NSInteger)focusReportingSearchFieldNumberOfResults:(iTermFocusReportingSearchField *)sender {
    __block NSInteger count = 0;
    [_results enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableArray<iTermGlobalSearchResult *> * _Nonnull obj, BOOL * _Nonnull stop) {
        count += obj.count;
    }];
    return count;
}

- (NSInteger)focusReportingSearchFieldCurrentIndex:(iTermFocusReportingSearchField *)sender {
    const NSInteger row = [_outlineView selectedRow];
    if (row == NSNotFound) {
        return 0;
    }
    id item = [_outlineView itemAtRow:row];
    iTermGlobalSearchResult *result = [iTermGlobalSearchResult castFrom:item];
    if (!result) {
        return 0;
    }
    NSInteger i = 0;
    for (NSString *guid in [self sortedNonEmptyResultSessionGUIDs]) {
        if (![guid isEqualToString:result.session.guid]) {
            i += _results[guid].count;
        } else {
            const NSInteger subindex = [_results[guid] indexOfObject:result];
            if (subindex == NSNotFound) {
                return 0;
            }
            i += subindex;
            return i + 1;
        }
    }
    return 0;
}

#pragma mark - NSOutlineViewDelegate

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(nullable NSTableColumn *)tableColumn
                            item:(id)item {
    NSString *guid = [NSString castFrom:item];
    if (guid) {
        // Session
        NSString *identifier = @"GlobalSearchSessionIdentifier";
        NSTableCellView *view = [outlineView makeViewWithIdentifier:identifier owner:self];
        if (!view) {
            view = [[NSTableCellView alloc] init];

            NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
            view.textField = textField;
            [view addSubview:textField];
            [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[textField]-0-|"
                                                                         options:0
                                                                         metrics:nil
                                                                           views:@{ @"textField": textField }]];
            [view addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                             attribute:NSLayoutAttributeCenterY
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:view
                                                             attribute:NSLayoutAttributeCenterY
                                                            multiplier:1
                                                              constant:0]];
            textField.frame = view.bounds;
            textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        }
        view.textField.stringValue = [[[[iTermController sharedInstance] sessionWithGUID:guid] name] removingHTMLFromTabTitleIfNeeded] ?: @"Session";
        return view;
    }

    iTermGlobalSearchResult *result = [iTermGlobalSearchResult castFrom:item];
    if (result) {
        // Search result
        NSString *identifier = @"GlobalSearchResultIdentifier";
        NSTableCellView *view = [outlineView makeViewWithIdentifier:identifier owner:self];
        if (!view) {
            view = [[NSTableCellView alloc] init];

            NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            view.textField = textField;
            [view addSubview:textField];
            [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[textField]-0-|"
                                                                         options:0
                                                                         metrics:nil
                                                                           views:@{ @"textField": textField }]];
            [view addConstraint:[NSLayoutConstraint constraintWithItem:textField
                                                             attribute:NSLayoutAttributeBottom
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:view
                                                             attribute:NSLayoutAttributeBottom
                                                            multiplier:1
                                                              constant:0]];
            textField.frame = view.bounds;
            textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        }
        view.textField.attributedStringValue = result.snippet;
        return view;
    }

    assert(NO);
    return nil;

}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    _ignoreClick = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_ignoreClick = NO;
    });
    [self revealSelection];
}

#pragma mark -  NSOutlineViewDataSource

- (NSDictionary<NSString *, NSMutableArray<iTermGlobalSearchResult *> *> *)nonEmptyResults {
    return [_results filteredWithBlock:^BOOL(NSString *key, NSMutableArray<iTermGlobalSearchResult *> *value) {
        return value.count > 0;
    }];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (item == nil) {
        return self.nonEmptyResults.count;
    }
    if ([item isKindOfClass:[NSString class]]) {
        return [_results[item] count];
    }
    return 0;
}

- (NSArray<NSString *> *)sortedNonEmptyResultSessionGUIDs {
    return [self.nonEmptyResults.allKeys sortedArrayUsingSelector:@selector(compare:)];
}
// An item is either nil (the root), a string (a session), or a iTermGlobalSearchResult object.
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (item == nil) {
        NSArray<NSString *> *sortedKeys = self.sortedNonEmptyResultSessionGUIDs;
        return sortedKeys[index];
    }
    if ([item isKindOfClass:[NSString class]]) {
        NSArray<iTermGlobalSearchResult *> *results = _results[item];
        assert(results);
        assert(index >= 0);
        assert(index < results.count);
        return results[index];
    }
    assert(false);
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (item == nil) {
        return YES;
    }
    if ([item isKindOfClass:[NSString class]]) {
        return YES;
    }
    return NO;
}

@end
