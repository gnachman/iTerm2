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

- (void)dealloc {
    [_accountNames release];
    [super dealloc];
}

- (void)reloadData {
    [_accountNames release];
    _accountNames = [[iTermPasswordManagerWindowController accountNamesWithFilter:nil] copy];
    if (!_accountNames.count) {
        _accountNames = [@[ @"" ] copy];
    }
}

- (NSString *)paramPlaceholder {
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
                                    stop:(BOOL *)stop {
    iTermApplicationDelegate *delegate = [iTermApplication.sharedApplication delegate];
    [delegate openPasswordManagerToAccountName:[self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                                         count:captureCount]
                                     inSession:aSession];
    return YES;
}

- (int)defaultIndex {
    return 0;
}

- (id)defaultPopupParameterObject {
    return @"";
}

@end
