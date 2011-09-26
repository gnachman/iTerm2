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

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSArray *)values;
- (void)tryString:(NSString *)s inSession:(PTYSession *)aSession;

// Subclasses must override this.
- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession;

- (NSComparisonResult)compareTitle:(Trigger *)other;

@end
