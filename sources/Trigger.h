//
//  Trigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>

#import "iTermFocusReportingTextField.h"
#import "iTermObject.h"
#import "iTermPromise.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class CapturedOutput;
@class PTYAnnotation;
@protocol PTYAnnotationReading;
@class Trigger;
@class iTermBackgroundCommandRunnerPool;
@protocol iTermObject;
@class iTermRateLimitedUpdate;
@class iTermStringLine;
@class iTermVariableScope;
@protocol PTYAnnotationReading;
@class Trigger;

extern NSString * const kTriggerRegexKey;
extern NSString * const kTriggerActionKey;
extern NSString * const kTriggerParameterKey;
extern NSString * const kTriggerPartialLineKey;
extern NSString * const kTriggerDisabledKey;

@protocol iTermTriggerDelegate<NSObject>
- (void)triggerDidChangeParameterOptions:(Trigger *)trigger;
@end

@protocol iTermTriggerCallbackScheduler<NSObject>
- (void)scheduleTriggerCallback:(void (^)(void))block;
@end

@protocol iTermTriggerScopeProvider<NSObject>
- (void)performBlockWithScope:(void (^)(iTermVariableScope *scope, id<iTermObject> object))block;
- (id<iTermTriggerCallbackScheduler>)triggerCallbackScheduler;
@end

@protocol iTermTriggerSession<NSObject>
- (void)triggerSessionRingBell:(Trigger *)trigger;
- (void)triggerSessionShowCapturedOutputTool:(Trigger *)trigger;
- (BOOL)triggerSessionIsShellIntegrationInstalled:(Trigger *)trigger;
- (void)triggerSessionShowShellIntegrationRequiredAnnouncement:(Trigger *)trigger;
- (void)triggerSession:(Trigger *)trigger didCaptureOutput:(CapturedOutput *)output;
- (void)triggerSessionShowCapturedOutputToolNotVisibleAnnouncementIfNeeded:(Trigger *)trigger;

// Identifier is used for silenceing errors, or nil to make it not silenceable.
- (void)triggerSession:(Trigger *)trigger launchCoprocessWithCommand:(NSString *)command identifier:(NSString * _Nullable)identifier silent:(BOOL)silent;
- (id<iTermTriggerScopeProvider>)triggerSessionVariableScopeProvider:(Trigger *)trigger;
- (BOOL)triggerSessionShouldUseInterpolatedStrings:(Trigger *)trigger;
- (void)triggerSession:(Trigger *)trigger postUserNotificationWithMessage:(NSString *)message rateLimit:(iTermRateLimitedUpdate *)rateLimit;
- (void)triggerSession:(Trigger *)trigger
  highlightTextInRange:(NSRange)rangeInScreenChars
          absoluteLine:(long long)lineNumber
                colors:(NSDictionary<NSString *, NSColor *> *)colors;
- (void)triggerSession:(Trigger *)trigger saveCursorLineAndStopScrolling:(BOOL)stopScrolling;
- (void)triggerSession:(Trigger *)trigger openPasswordManagerToAccountName:(NSString *)accountName;
- (void)triggerSession:(Trigger *)trigger
            runCommand:(NSString *)command
        withRunnerPool:(iTermBackgroundCommandRunnerPool *)pool;
- (void)triggerSession:(Trigger *)trigger writeText:(NSString *)text;
- (void)triggerSession:(Trigger *)trigger setRemoteHostName:(NSString *)remoteHost;
- (void)triggerSession:(Trigger *)trigger setCurrentDirectory:(NSString *)text;
- (void)triggerSession:(Trigger *)trigger didChangeNameTo:(NSString *)newName;
- (void)triggerSession:(Trigger *)trigger didDetectPromptAt:(VT100GridAbsCoordRange)range;
- (void)triggerSession:(Trigger *)trigger
    makeHyperlinkToURL:(NSURL *)url
               inRange:(NSRange)rangeInString
                  line:(long long)lineNumber;
- (void)triggerSession:(Trigger *)trigger
                invoke:(NSString *)invocation
         withVariables:(NSDictionary *)temporaryVariables
              captures:(NSArray<NSString *> *)captureStringArray;
- (void)triggerSession:(Trigger *)trigger
         setAnnotation:(id<PTYAnnotationReading>)annotation
              stringTo:(NSString *)stringValue;
- (void)triggerSession:(Trigger *)trigger
       highlightLineAt:(VT100GridAbsCoord)absCoord
                colors:(NSDictionary *)colors;
- (void)triggerSession:(Trigger *)trigger injectData:(NSData *)data;
- (void)triggerSession:(Trigger *)trigger setVariableNamed:(NSString *)name toValue:(id)value;
- (void)triggerSession:(Trigger *)trigger
  showAlertWithMessage:(NSString *)message
             rateLimit:(iTermRateLimitedUpdate *)rateLimit
               disable:(void (^)(void))disable;
- (id<PTYAnnotationReading> _Nullable)triggerSession:(Trigger *)trigger
                      makeAnnotationInRange:(NSRange)rangeInScreenChars
                                       line:(long long)lineNumber;

@end

@interface Trigger : NSObject<iTermObject>

@property (nonatomic, copy, readonly) NSString *regex;
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
@property (nonatomic, weak) id<iTermTriggerDelegate> delegate;

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
- (id _Nullable)objectAtIndex:(NSInteger)index;

// Utility that returns keys sorted by values for a tag/represented object dict
// (i.e., an element of groupedMenuItemsForPopupButton)
- (NSArray *)objectsSortedByValueInDict:(NSDictionary *)dict;

- (iTermVariableScope *)variableScope:(iTermVariableScope *)scope
               byAddingBackreferences:(NSArray<NSString *> *)backreferences;

- (iTermPromise<NSString *> *)paramWithBackreferencesReplacedWithValues:(NSArray<NSString *> *)strings
                                                                absLine:(long long)absLine
                                                                  scope:(id<iTermTriggerScopeProvider>)scope
                                                       useInterpolation:(BOOL)useInterpolation;

// Returns YES if no more triggers should be processed.
- (BOOL)tryString:(iTermStringLine *)stringLine
        inSession:(id<iTermTriggerSession>)aSession
      partialLine:(BOOL)partialLine
       lineNumber:(long long)lineNumber
 useInterpolation:(BOOL)useInterpolation;

// Subclasses must override this. Return YES if it can fire again on this line.
- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
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

- (id<iTermFocusReportingTextFieldDelegate> _Nullable)newParameterDelegateWithPassthrough:(id<NSTextFieldDelegate>)passthrough;

+ (NSDictionary *)triggerNormalizedDictionary:(NSDictionary *)dict;

- (NSDictionary *)dictionaryValue;

+ (NSDictionary *)sanitizedTriggerDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END

