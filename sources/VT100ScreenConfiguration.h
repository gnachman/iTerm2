//
//  VT100ScreenConfiguration.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import <Foundation/Foundation.h>
#import "ITAddressBookMgr.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

// Configuration info passed from PTYSession down to VT100Screen. This reduces the size of the
// delegate interface and will make it possible to move a bunch of code in VT100Screen off the main
// thread. In a multi-threaded design VT100Screen can never block on PTYSession and fetching config
// state is a very common cause of a synchronous dependency.
@protocol VT100ScreenConfiguration<NSObject, NSCopying>

// Shell integration: if a command ends without a terminal newline, should we inject one prior to the prompt?
@property (nonatomic, readonly) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readonly) NSString *sessionGuid;
@property (nonatomic, readonly) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readonly) NSInteger unicodeVersion;
@property (nonatomic, readonly) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readonly) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readonly) BOOL isTmuxClient;
@property (nonatomic, readonly) BOOL clipboardAccessAllowed;
@property (nonatomic, readonly) BOOL miniaturized;
// Screen-relative window frame.
@property (nonatomic, readonly) NSRect windowFrame;

// Is terminal-initiated printing allowed?
@property (nonatomic, readonly) BOOL printingAllowed;
@property (nonatomic, readonly) VT100GridSize theoreticalGridSize;
@property (nonatomic, readonly) NSString *iconTitle;
@property (nonatomic, readonly) NSString *windowTitle;
@property (nonatomic, readonly) BOOL clearScrollbackAllowed;
@property (nonatomic, readonly) NSString *profileName;
@property (nonatomic, readonly) NSSize cellSize;
@property (nonatomic, readonly) CGFloat backingScaleFactor;
@property (nonatomic, readonly) int maximumTheoreticalImageDimension;
@property (nonatomic, readonly) BOOL dimOnlyText;
@property (nonatomic, readonly) BOOL darkMode;
@property (nonatomic, readonly) BOOL useSeparateColorsForLightAndDarkMode;
@property (nonatomic, readonly) float minimumContrast;
@property (nonatomic, readonly) float faintTextAlpha;
@property (nonatomic, readonly) double mutingAmount;
@property (nonatomic, readonly) iTermUnicodeNormalization normalization;
@property (nonatomic, readonly) BOOL appendToScrollbackWithStatusBar;
@property (nonatomic, readonly) BOOL saveToScrollbackInAlternateScreen;
@property (nonatomic, readonly) BOOL unlimitedScrollback;
@property (nonatomic, readonly) BOOL reduceFlicker;
@property (nonatomic, readonly) int maxScrollbackLines;
@property (nonatomic, readonly) BOOL loggingEnabled;
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, id> *stringForKeypress;
@property (nonatomic, readonly) BOOL alertOnNextMark;
@property (nonatomic, readonly) double dimmingAmount;
@property (nonatomic, readonly) BOOL publishing;
@property (nonatomic, readonly) BOOL terminalCanChangeBlink;
@property (nonatomic, strong, readonly, nullable) NSNumber *desiredComposerRows;
@property (nonatomic, readonly) BOOL autoComposerEnabled;
@property (nonatomic, readonly) BOOL useLineStyleMarks;

@property (nonatomic, readonly) BOOL isDirty;

- (id<VT100ScreenConfiguration>)copy;

@end

@interface VT100ScreenConfiguration : NSObject<VT100ScreenConfiguration>
@end

@interface VT100MutableScreenConfiguration : VT100ScreenConfiguration

@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readwrite) NSInteger unicodeVersion;
@property (nonatomic, readwrite) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readwrite) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readwrite) BOOL isTmuxClient;
@property (nonatomic, readwrite) BOOL printingAllowed;
@property (nonatomic, readwrite) BOOL clipboardAccessAllowed;
@property (nonatomic, readwrite) BOOL miniaturized;
@property (nonatomic, readwrite) NSRect windowFrame;
@property (nonatomic, readwrite) VT100GridSize theoreticalGridSize;
@property (nonatomic, copy, readwrite) NSString *iconTitle;
@property (nonatomic, copy, readwrite) NSString *windowTitle;
@property (nonatomic, readwrite) BOOL clearScrollbackAllowed;
@property (nonatomic, copy, readwrite) NSString *profileName;
@property (nonatomic, readwrite) NSSize cellSize;
@property (nonatomic, readwrite) CGFloat backingScaleFactor;
@property (nonatomic, readwrite) int maximumTheoreticalImageDimension;
@property (nonatomic, readwrite) BOOL dimOnlyText;
@property (nonatomic, readwrite) BOOL darkMode;
@property (nonatomic, readwrite) BOOL useSeparateColorsForLightAndDarkMode;
@property (nonatomic, readwrite) float minimumContrast;
@property (nonatomic, readwrite) float faintTextAlpha;
@property (nonatomic, readwrite) double mutingAmount;
@property (nonatomic, readwrite) iTermUnicodeNormalization normalization;
@property (nonatomic, readwrite) BOOL appendToScrollbackWithStatusBar;
@property (nonatomic, readwrite) BOOL saveToScrollbackInAlternateScreen;
@property (nonatomic, readwrite) BOOL unlimitedScrollback;
@property (nonatomic, readwrite) BOOL reduceFlicker;
@property (nonatomic, readwrite) int maxScrollbackLines;
@property (nonatomic, readwrite) BOOL loggingEnabled;
@property (nonatomic, copy, readwrite) NSDictionary<NSNumber *, id> *stringForKeypress;
@property (nonatomic, copy) NSDictionary *stringForKeypressConfig;  // Used to tell if stringForKeypress needs to be updated.
@property (nonatomic, readwrite) BOOL alertOnNextMark;
@property (nonatomic, readwrite) double dimmingAmount;
@property (nonatomic, readwrite) BOOL publishing;
@property (nonatomic, readwrite) BOOL terminalCanChangeBlink;
@property (nonatomic, strong, readwrite, nullable) NSNumber *desiredComposerRows;
@property (nonatomic, readwrite) BOOL autoComposerEnabled;
@property (nonatomic, readwrite) BOOL useLineStyleMarks;

@property (nonatomic, readwrite) BOOL isDirty;

- (NSSet<NSString *> *)dirtyKeyPaths;

@end

NSDictionary *VT100ScreenConfigKeypressIdentifier(unsigned short keyCode,
                                                  NSEventModifierFlags flags,
                                                  NSString *characters,
                                                  NSString *charactersIgnoringModifiers);

NS_ASSUME_NONNULL_END
