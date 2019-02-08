//
//  Trigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>

@class iTermStringLine;
@class iTermVariableScope;
@class PTYSession;

extern NSString * const kTriggerRegexKey;
extern NSString * const kTriggerActionKey;
extern NSString * const kTriggerParameterKey;
extern NSString * const kTriggerPartialLineKey;

@interface Trigger : NSObject

@property (nonatomic, copy) NSString *regex;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) id param;
@property (nonatomic, assign) BOOL partialLine;
// A non-cryptographic hash for content addressed triggers (helpful for letting serialized data
// reference a trigger).
@property (nonatomic, readonly) NSData *digest;
@property (nonatomic, retain) NSColor *textColor;
@property (nonatomic, retain) NSColor *backgroundColor;

+ (Trigger *)triggerFromDict:(NSDictionary *)dict;
- (NSString *)action;
// Subclasses should implement:
- (NSString *)title;
- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation;
- (NSString *)triggerOptionalDefaultParameterValueWithInterpolation:(BOOL)interpolation;
// Returns true if this kind of action takes a parameter.
- (BOOL)takesParameter;
// Returns true if the parameter this action takes is a popupbutton.
- (BOOL)paramIsPopupButton;
- (BOOL)paramIsTwoColorWells;
// Returns a map from id(tag/represented object) -> NSString(title)
- (NSDictionary *)menuItemsForPoupupButton;
// Returns an array of NSDictionaries mapping NSNumber(tag) -> NSString(title)
- (NSArray *)groupedMenuItemsForPopupButton;

// Index of represented object (usually a NSNumber tag, but could be something else)
- (NSInteger)indexForObject:(id)object;
// Represented object (usually a NSNumber tag, but could be something else) at an index.
- (id)objectAtIndex:(NSInteger)index;

// Utility that returns keys sorted by values for a tag/represented object dict
// (i.e., an element of groupedMenuItemsForPopupButton)
- (NSArray *)objectsSortedByValueInDict:(NSDictionary *)dict;

- (iTermVariableScope *)variableScope:(iTermVariableScope *)scope
               byAddingBackreferences:(NSArray<NSString *> *)backreferences;

- (void)paramWithBackreferencesReplacedWithValues:(NSString *const *)strings
                                            count:(NSInteger)count
                                            scope:(iTermVariableScope *)scope
                                 useInterpolation:(BOOL)useInterpolation
                                       completion:(void (^)(NSString *result))completion;
- (void)paramWithBackreferencesReplacedWithValues:(NSArray *)strings
                                            scope:(iTermVariableScope *)scope
                                 useInterpolation:(BOOL)useInterpolation
                                       completion:(void (^)(NSString *result))completion;

// Returns YES if no more triggers should be processed.
- (BOOL)tryString:(iTermStringLine *)stringLine
        inSession:(PTYSession *)aSession
      partialLine:(BOOL)partialLine
       lineNumber:(long long)lineNumber
 useInterpolation:(BOOL)useInterpolation;

// Subclasses must override this. Return YES if it can fire again on this line.
- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)s
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop;

- (NSComparisonResult)compareTitle:(Trigger *)other;

// If no parameter is present, the parameter index to select by default.
- (int)defaultIndex;

// Default value for a parameter of a popup. Trigger's implementation returns
// @0 but subclasses can override.
- (id)defaultPopupParameterObject;

// Called before a trigger window opens.
- (void)reloadData;

- (id<NSTextFieldDelegate>)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough;

@end
