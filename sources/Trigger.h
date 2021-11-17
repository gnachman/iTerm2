//
//  Trigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>

#import "iTermFocusReportingTextField.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermObject;
@class iTermStringLine;
@class iTermVariableScope;
@class PTYSession;

extern NSString * const kTriggerRegexKey;
extern NSString * const kTriggerActionKey;
extern NSString * const kTriggerParameterKey;
extern NSString * const kTriggerPartialLineKey;
extern NSString * const kTriggerDisabledKey;

@interface Trigger : NSObject

@property (nonatomic, copy) NSString *regex;
@property (nonatomic, copy) NSString *action;
@property (nullable, nonatomic, copy) id param;
@property (nonatomic, assign) BOOL partialLine;
@property (nonatomic, assign) BOOL disabled;
// A non-cryptographic hash for content addressed triggers (helpful for letting serialized data
// reference a trigger).
@property (nullable, nonatomic, readonly) NSData *digest;
@property (nullable, nonatomic, retain) NSColor *textColor;
@property (nullable, nonatomic, retain) NSColor *backgroundColor;
@property (nonatomic, readonly) BOOL instantTriggerCanFireMultipleTimesPerLine;
@property (nonatomic, readonly) BOOL isIdempotent;
@property (class, nonatomic, readonly) NSString *title;

+ (nullable NSSet<NSString *> *)synonyms;
+ (nullable Trigger *)triggerFromDict:(NSDictionary *)dict;

// Subclasses should implement:
- (NSString *)title;
- (nullable NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation;
- (nullable NSString *)triggerOptionalDefaultParameterValueWithInterpolation:(BOOL)interpolation;
// Returns true if this kind of action takes a parameter.
- (BOOL)takesParameter;
// Returns true if the parameter this action takes is a popupbutton.
- (BOOL)paramIsPopupButton;
- (BOOL)paramIsTwoColorWells;
- (BOOL)paramIsTwoStrings;
// Returns a map from id(tag/represented object) -> NSString(title)
- (nullable NSDictionary *)menuItemsForPoupupButton;
// Returns an array of NSDictionaries mapping NSNumber(tag) -> NSString(title)
- (nullable NSArray *)groupedMenuItemsForPopupButton;

// Index of represented object (usually a NSNumber tag, but could be something else)
- (NSInteger)indexForObject:(id)object;
// Represented object (usually a NSNumber tag, but could be something else) at an index.
- (id)objectAtIndex:(NSInteger)index;

// Utility that returns keys sorted by values for a tag/represented object dict
// (i.e., an element of groupedMenuItemsForPopupButton)
- (NSArray *)objectsSortedByValueInDict:(NSDictionary *)dict;

- (iTermVariableScope *)variableScope:(iTermVariableScope *)scope
               byAddingBackreferences:(NSArray<NSString *> *)backreferences;

- (void)paramWithBackreferencesReplacedWithValues:(NSString * _Nonnull const * _Nonnull)strings
                                            count:(NSInteger)count
                                            scope:(iTermVariableScope *)scope
                                            owner:(id<iTermObject>)owner
                                 useInterpolation:(BOOL)useInterpolation
                                       completion:(void (^)(NSString *result))completion;

- (void)paramWithBackreferencesReplacedWithValues:(NSArray<NSString *> *)strings
                                            scope:(iTermVariableScope *)scope
                                            owner:(id<iTermObject>)owner
                                 useInterpolation:(BOOL)useInterpolation
                                       completion:(void (^)(NSString *result))completion;

// Returns YES if no more triggers should be processed.
- (BOOL)tryString:(iTermStringLine *)stringLine
        inSession:(PTYSession *)aSession
      partialLine:(BOOL)partialLine
       lineNumber:(long long)lineNumber
 useInterpolation:(BOOL)useInterpolation;

// Subclasses must override this. Return YES if it can fire again on this line.
- (BOOL)performActionWithCapturedStrings:(NSString * _Nonnull const * _Nonnull)capturedStrings
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

- (id<iTermFocusReportingTextFieldDelegate>)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough;

@end

NS_ASSUME_NONNULL_END

