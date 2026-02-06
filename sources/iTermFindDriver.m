//
//  iTermFindDriver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/4/18.
//

#import "iTermFindDriver.h"

#import "DebugLogging.h"
#import "FindContext.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDebouncer.h"
#import "iTermFindPasteboard.h"
#import "iTermSearchHistory.h"
#import "iTermTuple.h"
#import "iTermUserDefaults.h"

static iTermFindMode gFindMode;
static iTermFindMode gFilterMode;
static NSString *gSearchString;

@interface FindState : NSObject

@property(nonatomic, assign) iTermFindMode mode;
@property(nonatomic, copy) NSString *string;
@property(nonatomic, copy) void (^progress)(NSRange);
@end

@implementation FindState

- (instancetype)init {
    self = [super init];
    if (self) {
        _string = @"";
    }
    return self;
}

@end

@implementation iTermFindDriver {
    FindState *_savedState;
    FindState *_state;
    iTermSearchEngine *_searchEngine;
    iTermDebouncer *_debouncer;
    iTermFindMode _filterMode;
}

+ (iTermFindMode)mode {
    return gFindMode;
}

+ (iTermFindMode)filterMode {
    return gFilterMode;
}

+ (void)loadUserDefaults {
    {
        NSNumber *mode = [[iTermUserDefaults userDefaults] objectForKey:@"findMode_iTerm"];
        if (!mode) {
            // Migrate legacy value.
            NSNumber *ignoreCase = [[iTermUserDefaults userDefaults] objectForKey:@"findIgnoreCase_iTerm"];
            BOOL caseSensitive = ignoreCase ? ![ignoreCase boolValue] : NO;
            BOOL isRegex = [[iTermUserDefaults userDefaults] boolForKey:@"findRegex_iTerm"];

            if (caseSensitive && isRegex) {
                gFindMode = iTermFindModeCaseSensitiveRegex;
            } else if (!caseSensitive && isRegex) {
                gFindMode = iTermFindModeCaseInsensitiveRegex;
            } else if (caseSensitive && !isRegex) {
                gFindMode = iTermFindModeCaseSensitiveSubstring;
            } else if (!caseSensitive && !isRegex) {
                gFindMode = iTermFindModeSmartCaseSensitivity;  // Upgrade case-insensitive substring to smart case sensitivity.
            }
        } else {
            // Modern value
            gFindMode = [mode unsignedIntegerValue];
        }
    }
    {
        NSNumber *mode = [[iTermUserDefaults userDefaults] objectForKey:@"NoSyncFilterMode"];
        if (!mode) {
            gFilterMode = iTermFindModeSmartCaseSensitivity;
        } else {
            gFilterMode = [mode unsignedIntegerValue];
        }
    }
}

- (instancetype)initWithViewController:(NSViewController<iTermFindViewController> *)viewController
                  filterViewController:(NSViewController<iTermFilterViewController> *)filterViewController {
    self = [super init];
    if (self) {
        _viewController = viewController;
        _filterViewController = filterViewController;
        viewController.driver = self;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [iTermFindDriver loadUserDefaults];
        });
        _state = [[FindState alloc] init];
        _state.mode = gFindMode;
        _filterMode = gFilterMode;
        __weak __typeof(self) weakSelf = self;
        _debouncer = [[iTermDebouncer alloc] initWithCallback:^(NSString *query) {
            if (!weakSelf.viewController.view.isHidden) {
                [[iTermSearchHistory sharedInstance] addQuery:query];
                [weakSelf doSearch];
            }
        }];
        [[iTermFindPasteboard sharedInstance] addObserver:self block:^(id sender, NSString *newValue, BOOL internallyGenerated) {
            [weakSelf loadFindStringFromSharedPasteboard:newValue];
        }];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_searchEngine.timer invalidate];
    _searchEngine.timer = nil;
}

#pragma mark - APIs

- (iTermFindMode)mode {
    return _state.mode;
}

- (void)setMode:(iTermFindMode)mode {
    _state.mode = mode;
    [self setGlobalMode:mode];
}

- (iTermFindMode)filterMode {
    return _filterMode;
}

- (void)setFilterMode:(iTermFindMode)mode {
    _filterMode = mode;
    [self setGlobalFilterMode:mode];
}

- (void)setFindString:(NSString *)setFindString {
    [self setFindString:setFindString unconditionally:NO];
}

- (void)setFindStringUnconditionally:(NSString *)setFindString {
    [self setFindString:setFindString unconditionally:YES];
}

- (void)setFindString:(NSString *)setFindString unconditionally:(BOOL)unconditionally {
    _viewController.findString = setFindString;
    [self loadFindStringIntoSharedPasteboard:setFindString
                              userOriginated:unconditionally];
}

- (NSString *)findString {
    return _viewController.findString;
}

- (void)saveState {
    DLog(@"save mode=%@ string=%@", @(_savedState.mode), _savedState.string);
    _savedState = _state;
    _state = [[FindState alloc] init];
    _state.mode = _savedState.mode;
    _state.string = _savedState.string;
}

- (void)restoreState {
    _state = _savedState;
    _savedState = nil;
}

- (void)open {
    if (_savedState) {
        [self restoreState];
        _viewController.findString = _state.string;
    }
    
    _isVisible = YES;
    [self.delegate findViewControllerVisibilityDidChange:_viewController];
    [self.viewController open];
}

- (void)setDelegate:(id<iTermFindDriverDelegate>)delegate {
    _delegate = delegate;
    _searchEngine = [_delegate findDriverSearchEngine];
}

- (void)close {
    BOOL wasHidden = _viewController.view.isHidden;
    if (!wasHidden) {
        DLog(@"Remove timer");
        [_searchEngine.timer invalidate];
        _searchEngine.timer = nil;
    }
    [self updateDelayState];

    [self.viewController close];

    [_delegate findViewControllerClearSearch];
    [_delegate findViewControllerMakeDocumentFirstResponder];
    [self.delegate findViewControllerVisibilityDidChange:_viewController];
}

- (void)makeVisible {
    [self.viewController makeVisible];
}

- (void)closeViewAndDoTemporarySearchForString:(NSString *)string
                                          mode:(iTermFindMode)mode
                                      progress:(void (^)(NSRange linesSearched))progress {
    DLog(@"begin %@", self);
    [_viewController close];
    if (!_savedState) {
        [self saveState];
    }
    _state.mode = mode;
    _state.string = string;
    _state.progress = progress;
    _viewController.findString = string;
    DLog(@"delegate=%@ state=%@ state.mode=%@ state.string=%@", self.delegate, _state, @(_state.mode), _state.string);
    [self.delegate findViewControllerClearSearch];
    [self doSearch];
}

- (void)userDidEditFilter:(NSString *)updatedFilter {
    [_delegate findDriverSetFilter:updatedFilter withSideEffects:YES];
}

- (void)setFilterWithoutSideEffects:(NSString *)filter {
    [self.viewController setFilter:filter];
    [_delegate findDriverSetFilter:filter withSideEffects:NO];
}

- (void)highlightWithoutSelectingSearchResultsForQuery:(NSString *)string {
    self.findString = string;
    if (string.length == 0) {
        DLog(@"clear search");
        [_delegate findViewControllerClearSearch];
        return;
    }
    [[iTermSearchHistory sharedInstance] addQuery:string];
    [self setSearchDefaults];
    [self findSubString:string
       forwardDirection:![iTermAdvancedSettingsModel swapFindNextPrevious]
                   mode:_state.mode
             withOffset:-1
    scrollToFirstResult:NO
                  force:YES];
}

- (void)bottomUpPerformFindPanelAction:(id)sender {
    [self.delegate findDriverBottomUpPerformFindPanelAction:sender];
}

- (BOOL)bottomUpValidateMenuItem:(NSMenuItem *)menuItem {
    return [self.delegate findDriverBottomUpValidateMenuItem:menuItem];
}

- (BOOL)shouldSearchAutomatically {
    return [_viewController shouldSearchAutomatically];
}

- (void)userDidEditSearchQuery:(NSString *)updatedQuery
                   fieldEditor:(NSTextView *)fieldEditor {
    if (!_savedState) {
        [self loadFindStringIntoSharedPasteboard:_viewController.findString
                                  userOriginated:YES];
    }

    [_debouncer updateQuery:updatedQuery];
}

- (void)owningViewDidBecomeFirstResponder {
    [_debouncer owningViewDidBecomeFirstResponder];
    if (!self.needsUpdateOnFocus) {
        return;
    }
    if (!self.isVisible || ![self shouldSearchAutomatically]) {
        self.needsUpdateOnFocus = NO;
        return;
    }
    DLog(@"owning view became first responder, needs update on focus, and is visible. delegate = %@", self.delegate);
    self.needsUpdateOnFocus = NO;
    _savedState = nil;
    [self findSubString:_viewController.findString
       forwardDirection:![iTermAdvancedSettingsModel swapFindNextPrevious]
                   mode:_state.mode
             withOffset:-1
    scrollToFirstResult:NO
                  force:NO];
}

- (NSInteger)numberOfResults {
    return [self.delegate findDriverNumberOfSearchResults];
}

- (NSInteger)currentIndex {
    return [self.delegate findDriverCurrentIndex];
}

#pragma mark - Notifications

- (void)loadFindStringFromSharedPasteboard:(NSString *)value {
    DLog(@"[%p loadFindStringFromSharedPasteboard:%@] in window with frame %@", self, value, NSStringFromRect(_viewController.view.window.frame));
    if (![iTermAdvancedSettingsModel synchronizeQueryWithFindPasteboard]) {
        return;
    }
    if (!_viewController.view.window.isKeyWindow) {
        DLog(@"Not in key window");
        return;
    }
    if (_savedState && ![value isEqualTo:_savedState.string]) {
        [self setNeedsUpdateOnFocus:YES];
        [self restoreState];
    }
    if (![value isEqualToString:_viewController.findString]) {
        DLog(@"%@ setFindString:%@", self, value);
        _viewController.findString = value;
        self.needsUpdateOnFocus = self.needsUpdateOnFocus || _viewController.shouldSearchAutomatically;
    }
}

#pragma mark - Internal

- (void)setVisible:(BOOL)visible {
    if (visible != _isVisible) {
        _isVisible = visible;
        [self.delegate findViewControllerVisibilityDidChange:self.viewController];
        if (!visible && self.viewController.filterIsVisible) {
            [self.delegate findDriverFilterVisibilityDidChange:NO];
        }
    }
}

- (void)ceaseToBeMandatory {
    [self.delegate findViewControllerDidCeaseToBeMandatory:self.viewController];
}

- (void)setFilter:(NSString *)filter {
    [self.delegate findDriverSetFilter:filter withSideEffects:YES];
}

- (BOOL)loadFindStringIntoSharedPasteboard:(NSString *)stringValue
                            userOriginated:(BOOL)userOriginated {
    DLog(@"begin %@", self);
    if (_savedState) {
        DLog(@"Have no saved state, doing nothing");
        return YES;
    }
    // Copy into the NSPasteboardNameFind
    if (userOriginated) {
        [[iTermFindPasteboard sharedInstance] setStringValueUnconditionally:stringValue];
        return YES;
    } else {
        return [[iTermFindPasteboard sharedInstance] setStringValueIfAllowed:stringValue];
    }
}

- (void)backTab {
    if ([_delegate growSelectionLeft]) {
        NSString *text = [_delegate selectedText];
        if (text) {
            [_delegate copySelection];
            _viewController.findString = text;
            [self loadFindStringIntoSharedPasteboard:_viewController.findString
                                      userOriginated:YES];
            [_viewController deselectFindBarTextField];
        }
    }
}

- (void)forwardTab {
    [_delegate growSelectionRight];
    NSString *text = [_delegate selectedText];
    if (text) {
        [_delegate copySelection];
        _viewController.findString = text;
        [self loadFindStringIntoSharedPasteboard:text userOriginated:YES];
        [_viewController deselectFindBarTextField];
    }
}

- (void)copyPasteSelection {
    [_delegate copySelection];
    NSString* text = [_delegate unpaddedSelectedText];
    [_delegate pasteString:text];
    [_delegate findViewControllerMakeDocumentFirstResponder];
}

- (void)didLoseFocus {
    if (_searchEngine.timer == nil) {
        [_viewController setProgress:0];
        _state.progress = nil;
    }
    _lastEditTime = 0;
}

#pragma mark - Private

- (BOOL)continueSearch {
    DLog(@"begin self=%@", self);
    BOOL more = NO;
    if ([self.delegate findInProgress]) {
        DLog(@"Find is in progress");
        double progress;
        NSRange range;
        more = [self.delegate continueFind:&progress range:&range];
        if (_state.progress) {
            _state.progress(range);
        }
        [_viewController setProgress:progress];
    }
    if (!more) {
        [_searchEngine.timer invalidate];
        _searchEngine.timer = nil;
        DLog(@"Remove timer");
        [_viewController setProgress:1];
    }
    return more;
}

- (void)setSearchString:(NSString *)s {
    DLog(@"begin self=%@ s=%@", self, s);
    if (!_savedState) {
        DLog(@"Have no saved state so updating gSearchString and _state.string");
        gSearchString = [s copy];
        _state.string = [s copy];
    }
}

- (void)setGlobalMode:(iTermFindMode)set {
    if (!_savedState) {
        gFindMode = set;
        // The user defaults key got recycled to make it clear whether the legacy (number) or modern value (dict) is
        // in use, but the key doesn't reflect its true meaning any more.
        [[iTermUserDefaults userDefaults] setObject:@(set) forKey:@"findMode_iTerm"];
    }
}

- (void)setGlobalFilterMode:(iTermFindMode)set {
    if (!_savedState) {
        gFilterMode = set;
        // The user defaults key got recycled to make it clear whether the legacy (number) or modern value (dict) is
        // in use, but the key doesn't reflect its true meaning any more.
        [[iTermUserDefaults userDefaults] setObject:@(set) forKey:@"NoSyncFilterMode"];
    }
}

- (void)setSearchDefaults {
    DLog(@"begin %@", self);
    if (_viewController) {
        [self setSearchString:_viewController.findString];
    } else {
        [self setSearchString:[[iTermFindPasteboard sharedInstance] stringValue]];
    }
    [self setGlobalMode:_state.mode];
}

- (void)findSubString:(NSString *)subString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
           withOffset:(int)offset
  scrollToFirstResult:(BOOL)scrollToFirstResult
                force:(BOOL)force {
    DLog(@"begin self=%@ subString=%@ direction=%@ mode=%@ offset=%@ scrollToFirstResult=%@",
         self, subString, @(direction), @(mode), @(offset), @(scrollToFirstResult));
    BOOL ok = NO;
    if ([_delegate canSearch]) {
        DLog(@"delegate can search %@", _delegate);
        if ([subString length] <= 0) {
            DLog(@"Clear search");
            [_delegate findViewControllerClearSearch];
        } else {
            [_delegate findString:subString
                 forwardDirection:direction
                             mode:mode
                       withOffset:offset
              scrollToFirstResult:scrollToFirstResult
                            force:force];
            ok = YES;
        }
    }

    DLog(@"ok=%@ timer=%@", @(ok), _searchEngine.timer);
    if (ok && !_searchEngine.timer) {
        [_viewController setProgress:0];
        if ([self continueSearch]) {
            _searchEngine.timer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                                   target:self
                                                                 selector:@selector(continueSearch)
                                                                 userInfo:nil
                                                                  repeats:YES];
            DLog(@"Set timer");
            [[NSRunLoop currentRunLoop] addTimer:_searchEngine.timer
                                         forMode:NSRunLoopCommonModes];
        }
    } else if (!ok && _searchEngine.timer) {
        DLog(@"Remove timer");
        [_searchEngine.timer invalidate];
        _searchEngine.timer = nil;
        [_viewController setProgress:1];
        if (_state.progress) {
            _state.progress(NSMakeRange(0, NSUIntegerMax));
        }
    }
}

- (void)searchNext {
    [self setSearchDefaults];
    [self findSubString:_savedState ? _state.string : gSearchString
       forwardDirection:YES
                   mode:_state.mode
             withOffset:1
    scrollToFirstResult:YES
                  force:NO];
}

- (void)searchPrevious {
    [self setSearchDefaults];
    [self findSubString:_savedState ? _state.string : gSearchString
       forwardDirection:NO
                   mode:_state.mode
             withOffset:1
    scrollToFirstResult:YES
                  force:NO];
}

- (void)enterPressedWithShift:(BOOL)shiftPressed {
    if ([self.delegate findDriverEnterInFindPanelPerformsForwardSearch]) {
        [self searchNext];
        return;
    }
    const BOOL swap = [iTermAdvancedSettingsModel swapFindNextPrevious];
    if  (!shiftPressed ^ swap) {
        [self searchNext];
    } else {
        [self searchPrevious];
    }
}

- (void)doSearch {
    DLog(@"begin %@ _state.string=%@ _viewController.findString=%@", self, _state.string, _viewController.findString);
    NSString *theString = _savedState ? _state.string : _viewController.findString;
    if (!_savedState) {
        DLog(@"Have no saved state. Load find string into shared pasteboard: %@", _viewController.findString);
        [self loadFindStringIntoSharedPasteboard:_viewController.findString userOriginated:YES];
    }
    // Search.
    [self setSearchDefaults];
    [self findSubString:theString
       forwardDirection:![iTermAdvancedSettingsModel swapFindNextPrevious]
                   mode:_state.mode
             withOffset:-1
    scrollToFirstResult:YES
                  force:NO];
}

- (NSArray<NSString *> *)completionsForText:(NSString *)text
                                      range:(NSRange)range {
    NSArray<NSString *> *history = [[iTermSearchHistory sharedInstance] queries];
    if (text.length == 0) {
        return history;
    }
    if (range.location == NSNotFound) {
        return history;
    }
    NSString *prefix = [[text substringWithRange:range] localizedLowercaseString];
    return [[history flatMapWithBlock:^NSArray *(NSString *line) {
        return [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }] filteredArrayUsingBlock:^BOOL(NSString *word) {
        return [[word localizedLowercaseString] it_hasPrefix:prefix];
    }];
}

- (void)doCommandBySelector:(SEL)selector {
    if ([self respondsToSelector:selector]) {
        [self it_performNonObjectReturningSelector:selector withObject:nil];
    }
}

- (void)moveDown:(id)sender {
    NSTextView *fieldEditor = [NSTextView castFrom:[_viewController.view.window fieldEditor:YES
                                                                                  forObject:_viewController.view]];
    [fieldEditor complete:nil];
}

- (void)searchFieldWillBecomeFirstResponder:(NSSearchField *)searchField {
    [[iTermSearchHistory sharedInstance] coalescingFence];
}

- (void)eraseSearchHistory {
    [[iTermSearchHistory sharedInstance] eraseHistory];
}

- (void)toggleFilter {
    [self.viewController toggleFilter];
}

- (void)setFilterHidden:(BOOL)hidden {
    [self.viewController setFilterHidden:hidden];
}

- (void)invalidateFrame {
    [self.delegate findDriverInvalidateFrame];
}

- (void)filterVisibilityDidChange {
    [self.delegate findDriverFilterVisibilityDidChange:self.viewController.filterIsVisible];
}

- (void)setFilterProgress:(double)progress {
    [self.filterViewController ?: self.viewController setFilterProgress:progress];
}

@end
