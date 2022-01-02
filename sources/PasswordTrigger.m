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
    }
    return self;
}

- (void)reloadData {
    _accountNames = [[iTermPasswordManagerWindowController entriesWithFilter:nil] mapWithBlock:^id(iTermPasswordEntry *entry) {
        return entry.combinedAccountNameUserName;
    }];
    if (!_accountNames.count) {
        _accountNames = @[ @"" ];
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
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                              scope:[aSession triggerSessionVariableScopeProvider:self]
                                              owner:aSession
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull accountName) {
        [aSession triggerSession:self openPasswordManagerToAccountName:accountName];
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
