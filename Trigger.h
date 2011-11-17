//
//  Trigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>

@class PTYSession;

extern NSString * const kTriggerRegexKey;
extern NSString * const kTriggerActionKey;
extern NSString * const kTriggerParameterKey;

@interface Trigger : NSObject {
    NSString *regex_;
    NSString *action_;
    NSString *param_;
}

@property (nonatomic, copy) NSString *regex;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *param;

+ (Trigger *)triggerFromDict:(NSDictionary *)dict;
- (NSString *)action;
// Subclasses should implement:
- (NSString *)title;
- (BOOL)takesParameter;
- (NSString *)paramPlaceholder;
// Returns true if this kind of action takes a parameter.
- (BOOL)takesParameter;
// Returns true if the parameter this action takes is a popupbutton.
- (BOOL)paramIsPopupButton;
// Returns a map from NSNumber(tag) -> NSString(title)
- (NSDictionary *)menuItemsForPoupupButton;
// Index in tagsSortedByValue of "tag".
- (int)indexOfTag:(int)theTag;
// Tag at "index" in tagsSortedByValue.
- (int)tagAtIndex:(int)index;
// Tags in menu;ItemsForPopupButton sorted by value (however the subclass sees fit to sort)
- (NSArray *)tagsSortedByValue;

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSArray *)values;
- (void)tryString:(NSString *)s inSession:(PTYSession *)aSession;

// Subclasses must override this.
- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession;

- (NSComparisonResult)compareTitle:(Trigger *)other;

@end
