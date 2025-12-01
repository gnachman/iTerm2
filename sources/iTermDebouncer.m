//
//  iTermDebouncer.m
//  iTerm2SharedARC
//

#import "iTermDebouncer.h"
#import "iTermAdvancedSettingsModel.h"

// State machine states for debouncing
typedef NS_ENUM(NSInteger, iTermDebouncerState) {
    iTermDebouncerStateEmpty,
    iTermDebouncerStateDelaying,
    iTermDebouncerStateActiveShort,
    iTermDebouncerStateActiveMedium,
    iTermDebouncerStateActiveLong,
};

@implementation iTermDebouncer {
    // Callback to invoke when query should be executed
    void (^_callback)(NSString *query);

    // Current state in the state machine
    iTermDebouncerState _state;

    // Last time the query was edited
    NSTimeInterval _lastEditTime;

    // Current query string
    NSString *_currentQuery;
}

- (instancetype)initWithCallback:(void (^)(NSString *query))callback {
    self = [super init];
    if (self) {
        _callback = [callback copy];
        _state = iTermDebouncerStateEmpty;
        _lastEditTime = [NSDate timeIntervalSinceReferenceDate];
        _currentQuery = @"";
    }
    return self;
}

- (void)updateQuery:(NSString *)query {
    _currentQuery = query ?: @"";

    // A query becomes stale when it is 1 or 2 chars long and it hasn't been edited in 3 seconds.
    static const CGFloat kStaleTime = 3;
    BOOL isStale = (([NSDate timeIntervalSinceReferenceDate] - _lastEditTime) > kStaleTime &&
                    _currentQuery.length > 0 &&
                    [self queryIsShort:_currentQuery]);

    void (^execute)(void) = ^{
        if (self->_callback) {
            self->_callback(self->_currentQuery);
        }
    };

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
    switch (_state) {
        case iTermDebouncerStateEmpty:
            if (_currentQuery.length == 0) {
                break;
            } else if ([self queryIsShort:_currentQuery]) {
                [self startDelay];
            } else {
                [self becomeActive];
                execute();
            }
            break;

        case iTermDebouncerStateDelaying:
            if (_currentQuery.length == 0) {
                _state = iTermDebouncerStateEmpty;
            } else if (![self queryIsShort:_currentQuery]) {
                [self becomeActive];
                execute();
            }
            break;

        case iTermDebouncerStateActiveShort:
            // This differs from ActiveMedium in that it will not enter the Empty state.
            if (isStale) {
                [self startDelay];
                break;
            }

            execute();
            if ([self queryIsLong:_currentQuery]) {
                _state = iTermDebouncerStateActiveLong;
            } else if (![self queryIsShort:_currentQuery]) {
                _state = iTermDebouncerStateActiveMedium;
            }
            break;

        case iTermDebouncerStateActiveMedium:
            if (isStale) {
                [self startDelay];
                break;
            }
            if (_currentQuery.length == 0) {
                _state = iTermDebouncerStateEmpty;
            } else if ([self queryIsLong:_currentQuery]) {
                _state = iTermDebouncerStateActiveLong;
            }
            // This state intentionally does not transition to ActiveShort. If you backspace over
            // the whole query, the delay must be done again.
            execute();
            break;

        case iTermDebouncerStateActiveLong:
            if (_currentQuery.length == 0) {
                _state = iTermDebouncerStateEmpty;
                execute();
            } else if ([self queryIsShort:_currentQuery]) {
                // long->short transition. Common when select-all followed by typing.
                [self startDelay];
            } else if (![self queryIsLong:_currentQuery]) {
                _state = iTermDebouncerStateActiveMedium;
                execute();
            } else {
                execute();
            }
            break;
    }

    _lastEditTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)owningViewDidBecomeFirstResponder {
    // When the view becomes first responder, update the state if needed
    [self updateDelayState];
}

#pragma mark - Private Methods

- (void)startDelay {
    _state = iTermDebouncerStateDelaying;
    NSTimeInterval delay = [iTermAdvancedSettingsModel findDelaySeconds];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (self->_state == iTermDebouncerStateDelaying) {
                           [self becomeActive];
                           if (self->_callback) {
                               self->_callback(self->_currentQuery);
                           }
                       }
                   });
}

- (void)becomeActive {
    [self updateDelayState];
}

- (void)updateDelayState {
    if ([self queryIsLong:_currentQuery]) {
        _state = iTermDebouncerStateActiveLong;
    } else if ([self queryIsShort:_currentQuery]) {
        _state = iTermDebouncerStateActiveShort;
    } else {
        _state = iTermDebouncerStateActiveMedium;
    }
}

- (BOOL)queryIsLong:(NSString *)query {
    return query.length >= 5;
}

- (BOOL)queryIsShort:(NSString *)query {
    return query.length <= 2;
}

@end
