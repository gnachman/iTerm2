//
//  iTermFindDriver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/4/18.
//

#import "iTermFindDriver.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"

static iTermFindMode gFindMode;
static NSString *gSearchString;

@interface FindState : NSObject

@property(nonatomic, assign) iTermFindMode mode;
@property(nonatomic, copy) NSString *string;

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
    
    // Find runs out of a timer so that if you have a huge buffer then it
    // doesn't lock up. This timer runs the show.
    NSTimer *_timer;
    
    // Last time the text field was edited.
    NSTimeInterval _lastEditTime;
    enum {
        kFindViewDelayStateEmpty,
        kFindViewDelayStateDelaying,
        kFindViewDelayStateActiveShort,
        kFindViewDelayStateActiveMedium,
        kFindViewDelayStateActiveLong,
    } _delayState;
}

+ (void)loadUserDefaults {
    NSNumber *mode = [[NSUserDefaults standardUserDefaults] objectForKey:@"findMode_iTerm"];
    if (!mode) {
        // Migrate legacy value.
        NSNumber *ignoreCase = [[NSUserDefaults standardUserDefaults] objectForKey:@"findIgnoreCase_iTerm"];
        BOOL caseSensitive = ignoreCase ? ![ignoreCase boolValue] : NO;
        BOOL isRegex = [[NSUserDefaults standardUserDefaults] boolForKey:@"findRegex_iTerm"];
        
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

- (instancetype)initWithViewController:(NSViewController<iTermFindViewController> *)viewController {
    self = [super init];
    if (self) {
        _viewController = viewController;
        viewController.driver = self;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [iTermFindDriver loadUserDefaults];
        });
        _state = [[FindState alloc] init];
        _state.mode = gFindMode;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(loadFindStringFromSharedPasteboard:)
                                                     name:@"iTermLoadFindStringFromSharedPasteboard"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
}

#pragma mark - APIs

- (iTermFindMode)mode {
    return _state.mode;
}

- (void)setMode:(iTermFindMode)mode {
    _state.mode = mode;
    [self setGlobalMode:mode];
}

- (void)setFindString:(NSString *)setFindString {
    _viewController.findString = setFindString;
    [self loadFindStringIntoSharedPasteboard:setFindString];
}

- (NSString *)findString {
    return _viewController.findString;
}

- (void)saveState {
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

- (void)close {
    BOOL wasHidden = _viewController.view.isHidden;
    if (!wasHidden) {
        [_timer invalidate];
        _timer = nil;
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

- (void)closeViewAndDoTemporarySearchForString:(NSString *)string mode:(iTermFindMode)mode {
    [_viewController close];
    if (!_savedState) {
        [self saveState];
    }
    _state.mode = mode;
    _state.string = string;
    _viewController.findString = string;
    [self doSearch];
}

- (void)userDidEditSearchQuery:(NSString *)updatedQuery {
    // A query becomes stale when it is 1 or 2 chars long and it hasn't been edited in 3 seconds (or
    // the search field has lost focus since the last char was entered).
    static const CGFloat kStaleTime = 3;
    BOOL isStale = (([NSDate timeIntervalSinceReferenceDate] - _lastEditTime) > kStaleTime &&
                    updatedQuery.length > 0 &&
                    [self queryIsShort:updatedQuery]);

    // This state machine implements a delay before executing short (1 or 2 char) queries. The delay
    // is incurred again when a 5+ char query becomes short. It's kind of complicated so the delay
    // gets inserted at appropriate but minimally annoying times. Plug this into graphviz to see the
    // full state machine:
    //
    // digraph g {
    //   Empty -> Delaying [ label = "1 or 2 chars entered" ]
    //   Empty -> ActiveShort
    //   Empty -> ActiveMedium [ label = "3 or 4 chars entered" ]
    //   Empty -> ActiveLong [ label = "5+ chars entered" ]
    //
    //   Delaying -> Empty [ label = "Erased" ]
    //   Delaying -> ActiveShort [ label = "After Delay" ]
    //   Delaying -> ActiveMedium
    //   Delaying -> ActiveLong
    //
    //   ActiveShort -> ActiveMedium
    //   ActiveShort -> ActiveLong
    //   ActiveShort -> Delaying [ label = "When Stale" ]
    //
    //   ActiveMedium -> Empty
    //   ActiveMedium -> ActiveLong
    //   ActiveMedium -> Delaying [ label = "When Stale" ]
    //
    //   ActiveLong -> Delaying [ label = "Becomes Short" ]
    //   ActiveLong -> ActiveMedium
    //   ActiveLong -> Empty
    // }
    switch (_delayState) {
        case kFindViewDelayStateEmpty:
            if (updatedQuery.length == 0) {
                break;
            } else if ([self queryIsShort:updatedQuery]) {
                [self startDelay];
            } else {
                [self becomeActive];
            }
            break;

        case kFindViewDelayStateDelaying:
            if (updatedQuery.length == 0) {
                _delayState = kFindViewDelayStateEmpty;
            } else if (![self queryIsShort:updatedQuery]) {
                [self becomeActive];
            }
            break;

        case kFindViewDelayStateActiveShort:
            // This differs from ActiveMedium in that it will not enter the Empty state.
            if (isStale) {
                [self startDelay];
                break;
            }

            [self doSearch];
            if ([self queryIsLong:updatedQuery]) {
                _delayState = kFindViewDelayStateActiveLong;
            } else if (![self queryIsShort:updatedQuery]) {
                _delayState = kFindViewDelayStateActiveMedium;
            }
            break;

        case kFindViewDelayStateActiveMedium:
            if (isStale) {
                [self startDelay];
                break;
            }
            if (updatedQuery.length == 0) {
                _delayState = kFindViewDelayStateEmpty;
            } else if ([self queryIsLong:updatedQuery]) {
                _delayState = kFindViewDelayStateActiveLong;
            }
            // This state intentionally does not transition to ActiveShort. If you backspace over
            // the whole query, the delay must be done again.
            [self doSearch];
            break;

        case kFindViewDelayStateActiveLong:
            if (updatedQuery.length == 0) {
                _delayState = kFindViewDelayStateEmpty;
                [self doSearch];
            } else if ([self queryIsShort:updatedQuery]) {
                // long->short transition. Common when select-all followed by typing.
                [self startDelay];
            } else if (![self queryIsLong:updatedQuery]) {
                _delayState = kFindViewDelayStateActiveMedium;
                [self doSearch];
            } else {
                [self doSearch];
            }
            break;
    }
    _lastEditTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)owningViewDidBecomeFirstResponder {
    if (!self.needsUpdateOnFocus) {
        return;
    }
    if (!self.isVisible) {
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
    scrollToFirstResult:NO];
}

#pragma mark - Notifications

- (void)loadFindStringFromSharedPasteboard:(NSNotification *)notification {
    if (![iTermAdvancedSettingsModel loadFromFindPasteboard]) {
        return;
    }
    if (!_viewController.searchBarIsFirstResponder) {
        NSPasteboard* findBoard = [NSPasteboard pasteboardWithName:NSFindPboard];
        if ([[findBoard types] containsObject:NSStringPboardType]) {
            NSString *value = [findBoard stringForType:NSStringPboardType];
            if (value && [value length] > 0) {
                if (_savedState && ![value isEqualTo:_savedState.string]) {
                    [self setNeedsUpdateOnFocus:YES];
                    [self restoreState];
                }
                if (![value isEqualToString:_viewController.findString]) {
                    _viewController.findString = value;
                    self.needsUpdateOnFocus = YES;
                }
            }
        }
    }
}

#pragma mark - Internal

- (void)setVisible:(BOOL)visible {
    if (visible != _isVisible) {
        _isVisible = visible;
        [self.delegate findViewControllerVisibilityDidChange:self.viewController];
    }
}

- (void)ceaseToBeMandatory {
    [self.delegate findViewControllerDidCeaseToBeMandatory:self.viewController];
}

- (void)loadFindStringIntoSharedPasteboard:(NSString *)stringValue {
    if (_savedState) {
        return;
    }
    // Copy into the NSFindPboard
    NSPasteboard *findPB = [NSPasteboard pasteboardWithName:NSFindPboard];
    if (findPB) {
        [findPB declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [findPB setString:stringValue forType:NSStringPboardType];
    }
}

- (void)backTab {
    if ([_delegate growSelectionLeft]) {
        NSString *text = [_delegate selectedText];
        if (text) {
            [_delegate copySelection];
            _viewController.findString = text;
            [self loadFindStringIntoSharedPasteboard:_viewController.findString];
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
        [self loadFindStringIntoSharedPasteboard:text];
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
    _lastEditTime = 0;
}

#pragma mark - Private

- (BOOL)continueSearch {
    BOOL more = NO;
    if ([self.delegate findInProgress]) {
        double progress;
        more = [self.delegate continueFind:&progress];
        [_viewController setProgress:progress];
    }
    if (!more) {
        [_timer invalidate];
        _timer = nil;
        [_viewController setProgress:1];
    }
    return more;
}

- (void)setSearchString:(NSString *)s {
    if (!_savedState) {
        gSearchString = [s copy];
        _state.string = [s copy];
    }
}

- (void)setGlobalMode:(iTermFindMode)set {
    if (!_savedState) {
        gFindMode = set;
        // The user defaults key got recycled to make it clear whether the legacy (number) or modern value (dict) is
        // in use, but the key doesn't reflect its true meaning any more.
        [[NSUserDefaults standardUserDefaults] setObject:@(set) forKey:@"findMode_iTerm"];
    }
}

- (void)setSearchDefaults {
    [self setSearchString:_viewController.findString];
    [self setGlobalMode:_state.mode];
}

- (void)findSubString:(NSString *)subString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
           withOffset:(int)offset
  scrollToFirstResult:(BOOL)scrollToFirstResult {
    BOOL ok = NO;
    if ([_delegate canSearch]) {
        if ([subString length] <= 0) {
            [_delegate findViewControllerClearSearch];
        } else {
            [_delegate findString:subString
                 forwardDirection:direction
                             mode:mode
                       withOffset:offset
              scrollToFirstResult:scrollToFirstResult];
            ok = YES;
        }
    }

    if (ok && !_timer) {
        [_viewController setProgress:0];
        if ([self continueSearch]) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                      target:self
                                                    selector:@selector(continueSearch)
                                                    userInfo:nil
                                                     repeats:YES];
            [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        }
    } else if (!ok && _timer) {
        [_timer invalidate];
        _timer = nil;
        [_viewController setProgress:1];
    }
}

- (void)searchNext {
    [self setSearchDefaults];
    [self findSubString:_savedState ? _state.string : gSearchString
       forwardDirection:YES
                   mode:_state.mode
             withOffset:1
    scrollToFirstResult:YES];
}

- (void)searchPrevious {
    [self setSearchDefaults];
    [self findSubString:_savedState ? _state.string : gSearchString
       forwardDirection:NO
                   mode:_state.mode
             withOffset:1
    scrollToFirstResult:YES];
}

- (void)startDelay {
    _delayState = kFindViewDelayStateDelaying;
    NSTimeInterval delay = [iTermAdvancedSettingsModel findDelaySeconds];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (!self.viewController.view.isHidden &&
                           self->_delayState == kFindViewDelayStateDelaying) {
                           [self becomeActive];
                       }
                   });
}

- (BOOL)queryIsLong:(NSString *)query {
    return query.length >= 5;
}

- (BOOL)queryIsShort:(NSString *)query {
    return query.length <= 2;
}

- (void)becomeActive {
    [self updateDelayState];
    [self doSearch];
}

- (void)updateDelayState {
    if ([self queryIsLong:_viewController.findString]) {
        _delayState = kFindViewDelayStateActiveLong;
    } else if ([self queryIsShort:_viewController.findString]) {
        _delayState = kFindViewDelayStateActiveShort;
    } else {
        _delayState = kFindViewDelayStateActiveMedium;
    }
}

- (void)doSearch {
    NSString *theString = _savedState ? _state.string : _viewController.findString;
    if (!_savedState) {
        [self loadFindStringIntoSharedPasteboard:_viewController.findString];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                            object:nil];
    }
    // Search.
    [self setSearchDefaults];
    [self findSubString:theString
       forwardDirection:![iTermAdvancedSettingsModel swapFindNextPrevious]
                   mode:_state.mode
             withOffset:-1
    scrollToFirstResult:YES];
}

@end
