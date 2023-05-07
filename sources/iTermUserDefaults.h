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

@end

NS_ASSUME_NONNULL_END
