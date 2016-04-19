//
//  iTermPasteSpecialViewController.h
//  iTerm2
//
//  Created by George Nachman on 11/30/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PasteEvent.h"

extern NSString *const kPasteSpecialViewControllerUnicodePunctuationRegularExpression;
extern NSString *const kPasteSpecialViewControllerUnicodeDashesRegularExpression;
extern NSString *const kPasteSpecialViewControllerUnicodeDoubleQuotesRegularExpression;
extern NSString *const kPasteSpecialViewControllerUnicodeSingleQuotesRegularExpression;

@protocol iTermPasteSpecialViewControllerDelegate <NSObject>

- (void)pasteSpecialViewSpeedDidChange;
- (void)pasteSpecialTransformDidChange;

@end

@interface iTermPasteSpecialViewController : NSViewController

@property(nonatomic, assign) int chunkSize;
@property(nonatomic, assign) NSTimeInterval delayBetweenChunks;
@property(nonatomic, assign) id<iTermPasteSpecialViewControllerDelegate> delegate;

@property(nonatomic, assign) int numberOfSpacesPerTab;
@property(nonatomic, assign, getter=areTabTransformsEnabled) BOOL enableTabTransforms;
@property(nonatomic, assign) NSInteger selectedTabTransform;
@property(nonatomic, assign, getter=isConvertNewlinesEnabled) BOOL enableConvertNewlines;
@property(nonatomic, assign) BOOL shouldConvertNewlines;
@property(nonatomic, assign, getter=isRemoveNewlinesEnabled) BOOL enableRemoveNewlines;
@property(nonatomic, assign) BOOL shouldRemoveNewlines;
@property(nonatomic, assign, getter=isEscapeShellCharsWithBackslashEnabled) BOOL enableEscapeShellCharsWithBackslash;
@property(nonatomic, assign) BOOL shouldEscapeShellCharsWithBackslash;
@property(nonatomic, assign, getter=isRemoveControlCodesEnabled) BOOL enableRemoveControlCodes;
@property(nonatomic, assign) BOOL shouldRemoveControlCodes;
@property(nonatomic, assign, getter=isBracketedPasteEnabled) BOOL enableBracketedPaste;
@property(nonatomic, assign) BOOL shouldUseBracketedPasteMode;
@property(nonatomic, assign, getter=isBase64Enabled) BOOL enableBase64;
@property(nonatomic, assign) BOOL shouldBase64Encode;
@property(nonatomic, assign, getter=isUseRegexSubstitutionEnabled) BOOL enableUseRegexSubstitution;
@property(nonatomic, assign) BOOL shouldUseRegexSubstitution;
@property(nonatomic, assign, getter=isWaitForPromptEnabled) BOOL enableWaitForPrompt;
@property(nonatomic, assign) BOOL shouldWaitForPrompt;
@property(nonatomic, assign, getter=isConvertUnicodePunctuationEnabled) BOOL enableConvertUnicodePunctuation;
@property(nonatomic, assign) BOOL shouldConvertUnicodePunctuation;
@property(nonatomic, retain) NSString *regexString;
@property(nonatomic, retain) NSString *substitutionString;

@property(nonatomic, readonly) NSString *stringEncodedSettings;
@property(nonatomic, readonly) iTermPasteFlags flags;

+ (NSString *)descriptionForCodedSettings:(NSString *)jsonString;
+ (PasteEvent *)pasteEventForConfig:(NSString *)jsonConfig string:(NSString *)string;

- (NSString *)descriptionForDuration:(NSTimeInterval)duration;
- (void)loadSettingsFromString:(NSString *)jsonString;

@end
