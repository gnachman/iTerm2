//
//  Trigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import "DebugLogging.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "ScreenChar.h"
#import <CommonCrypto/CommonDigest.h>

NSString * const kTriggerRegexKey = @"regex";
NSString * const kTriggerActionKey = @"action";
NSString * const kTriggerParameterKey = @"parameter";
NSString * const kTriggerPartialLineKey = @"partial";

@implementation Trigger {
    // The last absolute line number on which this trigger fired for a partial
    // line. -1 means it has not fired on the current line.
    long long _lastLineNumber;
    NSString *regex_;
    NSString *action_;
    id param_;
}

@synthesize regex = regex_;
@synthesize action = action_;
@synthesize param = param_;

+ (Trigger *)triggerFromDict:(NSDictionary *)dict
{
    NSString *className = [dict objectForKey:kTriggerActionKey];
    if ([className isEqualToString:@"iTermUserNotificationTrigger"]) {
        // I foolishly renamed the class in 3.2.1, which broke everyone's triggers. It got renamed
        // back in 3.2.2. If someone created a new trigger in 3.2.1 it would have the bogus name.
        className = @"GrowlTrigger";
    }
    Class class = NSClassFromString(className);
    Trigger *trigger = [[[class alloc] init] autorelease];
    trigger.regex = dict[kTriggerRegexKey];
    trigger.param = dict[kTriggerParameterKey];
    trigger.partialLine = [dict[kTriggerPartialLineKey] boolValue];
    return trigger;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastLineNumber = -1;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p regex=%@ param=%@>",
               NSStringFromClass(self.class), self, self.regex, self.param];
}
- (NSString *)action
{
    return NSStringFromClass([self class]);
}

- (NSString *)title
{
    assert(false);
}

- (NSString *)paramPlaceholder
{
    assert(false);
}

- (NSString *)paramDefault
{
    return nil;
}

- (BOOL)takesParameter
{
    assert(false);
}

- (BOOL)paramIsPopupButton {
    return NO;
}

- (BOOL)paramIsTwoColorWells {
    return NO;
}

- (NSDictionary *)menuItemsForPoupupButton
{
    return nil;
}

- (NSArray *)groupedMenuItemsForPopupButton
{
  NSDictionary *menuItems = [self menuItemsForPoupupButton];
  if (menuItems) {
    return @[ menuItems ];
  } else {
    return nil;
  }
}

- (id<NSTextFieldDelegate>)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough {
    return nil;
}

- (void)dealloc {
    [regex_ release];
    [action_ release];
    [param_ release];
    [_backgroundColor release];
    [_textColor release];
    [super dealloc];
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    assert(false);
    return NO;
}

- (BOOL)tryString:(iTermStringLine *)stringLine
        inSession:(PTYSession *)aSession
      partialLine:(BOOL)partialLine
       lineNumber:(long long)lineNumber {
    if (_partialLine && _lastLineNumber == lineNumber) {
        // Already fired a on a partial line on this line.
        if (!partialLine) {
            _lastLineNumber = -1;
        }
        return NO;
    }
    if (partialLine && !_partialLine) {
        // This trigger doesn't support partial lines.
        return NO;
    }

    __block BOOL stopFutureTriggersFromRunningOnThisLine = NO;
    NSString *s = stringLine.stringValue;
    [s enumerateStringsMatchedByRegex:regex_
                           usingBlock:^(NSInteger captureCount,
                                        NSString *const *capturedStrings,
                                        const NSRange *capturedRanges,
                                        volatile BOOL *const stopEnumerating) {
                               _lastLineNumber = lineNumber;
                               DLog(@"Trigger %@ matched string %@", self, s);
                               if (![self performActionWithCapturedStrings:capturedStrings
                                                            capturedRanges:capturedRanges
                                                              captureCount:captureCount
                                                                 inSession:aSession
                                                                  onString:stringLine
                                                      atAbsoluteLineNumber:lineNumber
                                                                      stop:&stopFutureTriggersFromRunningOnThisLine]) {
                                   *stopEnumerating = YES;
                               }
                           }];
    if (!partialLine) {
        _lastLineNumber = -1;
    }
    return stopFutureTriggersFromRunningOnThisLine;
}

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSArray *)strings {
    NSString *temp[10];
    int i;
    for (i = 0; i < strings.count; i++) {
        temp[i] = strings[i];
    }
    return [self paramWithBackreferencesReplacedWithValues:temp count:i];
}

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSString * const*)strings
                                                  count:(NSInteger)count {
    NSString *p = self.param;

    for (int i = 0; i < 9; i++) {
        NSString *rep = @"";
        if (count > i) {
            rep = strings[i];
        }
        p = [p stringByReplacingBackreference:i withString:rep];
    }
    p = [p stringByReplacingEscapedChar:'a' withString:@"\x07"];
    p = [p stringByReplacingEscapedChar:'b' withString:@"\x08"];
    p = [p stringByReplacingEscapedChar:'e' withString:@"\x1b"];
    p = [p stringByReplacingEscapedChar:'n' withString:@"\n"];
    p = [p stringByReplacingEscapedChar:'r' withString:@"\r"];
    p = [p stringByReplacingEscapedChar:'t' withString:@"\t"];
    p = [p stringByReplacingEscapedChar:'\\' withString:@"\\"];
    p = [p stringByReplacingEscapedHexValuesWithChars];
    return p;
}

- (NSComparisonResult)compareTitle:(Trigger *)other
{
    return [[self title] compare:[other title]];
}

- (NSInteger)indexForObject:(id)object {
    return [object intValue];
}

- (id)objectAtIndex:(NSInteger)index {
    return @(index);
}

- (NSArray *)objectsSortedByValueInDict:(NSDictionary *)dict
{
    return [dict keysSortedByValueUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (int)defaultIndex {
    return 0;
}

- (id)defaultPopupParameterObject {
    return @0;
}

// Called before a trigger window opens.
- (void)reloadData {
}

- (NSData *)digest {
    NSDictionary *triggerDictionary = @{ kTriggerActionKey: NSStringFromClass(self.class),
                                         kTriggerRegexKey: self.regex ?: @"",
                                         kTriggerParameterKey: self.param ?: @"",
                                         kTriggerPartialLineKey: @(self.partialLine) };

    // Glom all the data together as key=value\nkey=value\n...
    NSMutableString *temp = [NSMutableString string];
    for (NSString *key in [[triggerDictionary allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [temp appendFormat:@"%@=%@\n", key, triggerDictionary[key]];
    }

    NSData *data = [temp dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    if (CC_SHA1([data bytes], [data length], hash) ) {
        NSData *sha1 = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
        return sha1;
    } else {
        return data;
    }
}

@end
