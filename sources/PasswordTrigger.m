//
//  PasswordTrigger.m
//  iTerm
//
//  Created by George Nachman on 5/15/14.
//
//

#import "PasswordTrigger.h"
#import "iTermPasswordManagerWindowController.h"
#import "NSArray+iTerm.h"

static NSString *PasswordTriggerPlaceholderString = @"Open Password Manager to Unlock";

@interface PasswordTrigger ()
@property(nonatomic, copy) NSArray *accountNames;
@end

@implementation PasswordTrigger

+ (NSString *)title {
    return @"Open Password Manager…";
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reloadData];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(passwordManagerDidLoadAccounts:)
                                                     name:iTermPasswordManagerDidLoadAccounts
                                                   object:nil];
    }
    return self;
}

- (void)passwordManagerDidLoadAccounts:(NSNotification *)notification {
    [self reloadData];
    [self.delegate triggerDidChangeParameterOptions:self];
}

- (id)param {
    NSString *value = [super param];
    if ([value isEqual:PasswordTriggerPlaceholderString]) {
        return @"";
    }
    return value;
}

- (void)reloadData {
    _accountNames = [iTermPasswordManagerWindowController cachedCombinedAccountNames];
    [self addUnlockToAccountNamesIfNeeded];
}

- (void)addUnlockToAccountNamesIfNeeded {
    if (![_accountNames filteredArrayUsingBlock:^BOOL(id anObject) {
        return ![anObject isEqual:PasswordTriggerPlaceholderString];
    }].count) {
        NSString *param = [NSString castFrom:[self param]];
        if (param.length > 0) {
            _accountNames = @[ param, PasswordTriggerPlaceholderString ];
        } else {
            _accountNames = @[ PasswordTriggerPlaceholderString ];
        }
    }
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"";
}

- (BOOL)takesParameter {
    return YES;
}

- (BOOL)paramIsPopupButton {
    return YES;
}

- (NSArray *)sortedAccountNames {
    return [_accountNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSInteger)indexForObject:(id)object {
    NSUInteger index = [[self sortedAccountNames] indexOfObject:object];
    if (index == NSNotFound) {
        return -1;
    } else {
        return index;
    }
}

- (id)objectAtIndex:(NSInteger)index {
    if (index < 0 || index >= _accountNames.count) {
        return nil;
    }
    return [self sortedAccountNames][index];
}

- (NSDictionary *)menuItemsForPoupupButton {
    [self addUnlockToAccountNamesIfNeeded];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *name in _accountNames) {
        result[name] = name;
    }
    return result;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    // Need to stop the world to get scope, provided it is needed. Password manager opens are so slow & rare that this is ok.
    id<iTermTriggerScopeProvider> scopeProvider = [aSession triggerSessionVariableScopeProvider:self];
    id<iTermTriggerCallbackScheduler> scheduler = [scopeProvider triggerCallbackScheduler];
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                             absLine:lineNumber
                                               scope:scopeProvider
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull accountName) {
        [scheduler scheduleTriggerCallback:^{
            [aSession triggerSession:self openPasswordManagerToAccountName:accountName];
        }];
    }];
    return YES;
}

- (int)defaultIndex {
    return 0;
}

- (id)defaultPopupParameterObject {
    return @"";
}

@end
