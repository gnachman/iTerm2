//
//  Trigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import "RegexKitLite.h"
#import "NSStringITerm.h"
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
    NSString *param_;
}

@synthesize regex = regex_;
@synthesize action = action_;
@synthesize param = param_;

+ (Trigger *)triggerFromDict:(NSDictionary *)dict
{
    NSString *className = [dict objectForKey:kTriggerActionKey];
    Class class = NSClassFromString(className);
    Trigger *trigger = [[[class alloc] init] autorelease];
    trigger.regex = dict[kTriggerRegexKey];
    trigger.param = dict[kTriggerParameterKey];
    trigger.partialLine = [dict[kTriggerPartialLineKey] boolValue];
    return trigger;
}

- (id)init {
    self = [super init];
    if (self) {
        _lastLineNumber = -1;
    }
    return self;
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

- (BOOL)takesParameter
{
    assert(false);
}

- (BOOL)paramIsPopupButton
{
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

- (void)dealloc {
    [regex_ release];
    [action_ release];
    [param_ release];
    [super dealloc];
}

- (BOOL)performActionWithValues:(NSArray *)values
                      inSession:(PTYSession *)aSession
                       onString:(NSString *)string
           atAbsoluteLineNumber:(long long)absoluteLineNumber
                           stop:(BOOL *)stop {
    assert(false);
    return NO;
}

- (BOOL)tryString:(NSString *)s
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
    NSRange range = [s rangeOfRegex:regex_];
    BOOL stop = NO;
    if (range.location != NSNotFound) {
        NSArray *captures = [s arrayOfCaptureComponentsMatchedByRegex:regex_];
        if (captures.count) {
            _lastLineNumber = lineNumber;
        }
        for (NSArray *matches in captures) {
            if (![self performActionWithValues:matches
                                    inSession:aSession
                                     onString:s
                          atAbsoluteLineNumber:lineNumber
                                          stop:&stop]) {
                break;
            }
        }
    }
    if (!partialLine) {
        _lastLineNumber = -1;
    }
    return stop;
}

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSArray *)values
{
    NSString *p = self.param;
    for (int i = 0; i < 9; i++) {
        NSString *rep = @"";
        if (values.count > i) {
            rep = [values objectAtIndex:i];
        }
        p = [p stringByReplacingBackreference:i withString:rep];
    }
    p = [p stringByReplacingEscapedChar:'a' withString:@"\x07"];
    p = [p stringByReplacingEscapedChar:'b' withString:@"\x08"];
    p = [p stringByReplacingEscapedChar:'e' withString:@"\x1b"];
    p = [p stringByReplacingEscapedChar:'n' withString:@"\n"];
    p = [p stringByReplacingEscapedChar:'r' withString:@"\r"];
    p = [p stringByReplacingEscapedChar:'t' withString:@"\t"];
    p = [p stringByReplacingEscapedHexValuesWithChars];
    return p;
}

- (NSComparisonResult)compareTitle:(Trigger *)other
{
    return [[self title] compare:[other title]];
}

- (int)indexOfTag:(int)theTag
{
    return theTag;
}

- (int)tagAtIndex:(int)theIndex
{
    return 0;
}

- (int)indexForObject:(id)object {
    return [self indexOfTag:[object intValue]];
}

- (id)objectAtIndex:(int)index {
    int tag = [self tagAtIndex:index];
    if (tag < 0) {
        return nil;
    } else {
        return @(tag);
    }
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
