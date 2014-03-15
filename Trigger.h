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
- (NSString *)paramPlaceholder;
// Returns true if this kind of action takes a parameter.
- (BOOL)takesParameter;
// Returns true if the parameter this action takes is a popupbutton.
- (BOOL)paramIsPopupButton;
// Returns a map from NSNumber(tag) -> NSString(title)
- (NSDictionary *)menuItemsForPoupupButton;
// Returns an array of NSDictionaries mapping NSNumber(tag) -> NSString(title)
- (NSArray *)groupedMenuItemsForPopupButton;
// Index of "tag" in menu; inverse of tagAtIndex.
- (int)indexOfTag:(int)theTag;
// Tag at "index" in menu.
- (int)tagAtIndex:(int)index;

// Utility that returns keys sorted by values for a tag dict (i.e., an element of groupedMenuItemsForPopupButton)
- (NSArray *)tagsSortedByValueInDict:(NSDictionary *)dict;

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSArray *)values;
- (void)tryString:(NSString *)s inSession:(PTYSession *)aSession;

// Subclasses must override this.
- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession;

- (NSComparisonResult)compareTitle:(Trigger *)other;

// If no parameter is present, the parameter index to select by default.
- (int)defaultIndex;

@end
