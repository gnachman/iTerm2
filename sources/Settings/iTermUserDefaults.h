//
//  iTermUserDefaults.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kSelectionRespectsSoftBoundariesKey;

@interface iTermUserDefaults : NSObject

// Call this before any access to +userDefaults to use a custom suite instead of standardUserDefaults.
+ (void)setCustomSuiteName:(nullable NSString *)suiteName;

// Returns the custom suite name if one was set via setCustomSuiteName:, otherwise nil.
+ (nullable NSString *)customSuiteName;

// Returns the custom suite if set, otherwise standardUserDefaults.
+ (NSUserDefaults *)userDefaults;

+ (void)performMigrations;

@property (class, nonatomic, copy) NSArray<NSString *> *searchHistory;
@property (class, nonatomic) BOOL secureKeyboardEntry;
@property (class, nonatomic) BOOL enableAutomaticProfileSwitchingLogging;

typedef NS_ENUM(NSUInteger, iTermAppleWindowTabbingMode) {
    iTermAppleWindowTabbingModeAlways,
    iTermAppleWindowTabbingModeFullscreen,
    iTermAppleWindowTabbingModeManual
};

@property (class, nonatomic, readonly) iTermAppleWindowTabbingMode appleWindowTabbingMode;
@property (class, nonatomic) BOOL haveBeenWarnedAboutTabDockSetting;
@property (class, nonatomic) BOOL requireAuthenticationAfterScreenLocks;
@property (class, nonatomic) BOOL openTmuxDashboardIfHiddenWindows;
@property (class, nonatomic) BOOL haveExplainedHowToAddTouchbarControls;
@property (class, nonatomic) BOOL ignoreSystemWindowRestoration;
@property (class, nonatomic) NSUInteger globalSearchMode;
@property (class, nonatomic) BOOL addTriggerInstant;
@property (class, nonatomic) BOOL addTriggerUpdateProfile;
@property (class, nonatomic, copy) NSString *lastSystemPythonVersionRequirement;
@property (class, nonatomic) BOOL probeForPassword;
@property (class, nonatomic, copy, nullable) NSString *importPath;
@property (class, nonatomic) BOOL shouldSendReturnAfterPassword;
@property (class, nonatomic, copy, nullable) NSDictionary<NSString *, NSNumber *> *windowCornerRadiusCache;

// Returns whether the previous process exited cleanly. The value is latched on
// first access: the on-disk flag is read then immediately reset so that if this
// process crashes before +markShutdownAsClean is called, the next launch will
// correctly see the previous shutdown as unclean. Subsequent calls return the
// cached value from first access.
@property (class, nonatomic, readonly) BOOL lastShutdownWasClean;

// Call during clean application termination to record that this launch ended
// cleanly. Writes to disk and synchronizes.
+ (void)markShutdownAsClean;

@end

NS_ASSUME_NONNULL_END
