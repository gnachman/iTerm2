//
//  iTermDebouncer.m
//  iTerm2SharedARC
//

#import "iTermDebouncer.h"
#import "iTermAdvancedSettingsModel.h"

typedef NS_ENUM(NSInteger, iTermDebouncerState) {
    iTermDebouncerStateEmpty,
    iTermDebouncerStateDelaying,
    iTermDebouncerStateActiveShort,
    iTermDebouncerStateActiveMedium,
    iTermDebouncerStateActiveLong,
};

@implementation iTermDebouncer {
    void (^_callback)(NSString *query);
    iTermDebouncerState _state;
    NSTimeInterval _lastEditTime;
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

    static const CGFloat kStaleTime = 3;
    BOOL isStale = (([NSDate timeIntervalSinceReferenceDate] - _lastEditTime) > kStaleTime &&
                    _currentQuery.length > 0 &&
                    [self queryIsShort:_currentQuery]);

    void (^execute)(void) = ^{
        if (self->_callback) {
            self->_callback(self->_currentQuery);
        }
    };

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
            execute();
            break;

        case iTermDebouncerStateActiveLong:
            if (_currentQuery.length == 0) {
                _state = iTermDebouncerStateEmpty;
                execute();
            } else if ([self queryIsShort:_currentQuery]) {
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
