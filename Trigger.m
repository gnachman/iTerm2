//
//  Trigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "Trigger.h"
#import "RegexKitLite.h"
#import "NSStringITerm.h"

NSString * const kTriggerRegexKey = @"regex";
NSString * const kTriggerActionKey = @"action";
NSString * const kTriggerParameterKey = @"parameter";

@implementation Trigger

@synthesize regex = regex_;
@synthesize action = action_;
@synthesize param = param_;

+ (Trigger *)triggerFromDict:(NSDictionary *)dict
{
    NSString *className = [dict objectForKey:kTriggerActionKey];
    Class class = NSClassFromString(className);
    Trigger *trigger = [[[class alloc] init] autorelease];
    trigger.regex = [dict objectForKey:kTriggerRegexKey];
    trigger.param = [dict objectForKey:kTriggerParameterKey];
    return trigger;
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
    return [NSArray arrayWithObject:menuItems];
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

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    assert(false);
}

- (void)tryString:(NSString *)s inSession:(PTYSession *)aSession
{
    NSRange range = [s rangeOfRegex:regex_];
    if (range.location != NSNotFound) {
        NSArray *captures = [s arrayOfCaptureComponentsMatchedByRegex:regex_];
        for (NSArray *matches in captures) {
            [self performActionWithValues:matches
                                inSession:aSession];
        }
    }
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

- (NSArray *)tagsSortedByValueInDict:(NSDictionary *)dict
{
    return [dict keysSortedByValueUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (int)defaultIndex {
    return 0;
}

@end
