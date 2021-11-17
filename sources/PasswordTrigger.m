//
//  PasswordTrigger.m
//  iTerm
//
//  Created by George Nachman on 5/15/14.
//
//

#import "PasswordTrigger.h"
#import "iTermApplicationDelegate.h"
#import "iTermPasswordManagerWindowController.h"
#import "NSArray+iTerm.h"
#import "PTYSession.h"

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

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:aSession.variablesScope
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *accountName) {
                                             if (accountName) {
                                                 iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
                                                 [itad openPasswordManagerToAccountName:accountName
                                                                                  inSession:aSession];
                                             }
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
