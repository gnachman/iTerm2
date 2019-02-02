//
//  iTermLaunchExperienceController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/14/19.
//

#import "iTermLaunchExperienceController.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermOnboardingWindowController.h"
#import "iTermPreferences.h"
#import "iTermTipController.h"
#import "iTermWarning.h"
#import "PFMoveApplication.h"

@import Sparkle;

static NSString *const kHaveWarnedAboutPasteConfirmationChange = @"NoSyncHaveWarnedAboutPasteConfirmationChange";
static NSString *const iTermLaunchExperienceControllerNextAnnoyanceTime = @"NoSyncNextAnnoyanceTime";
static NSString *const iTermLaunchExperienceControllerRunCount = @"NoSyncLaunchExperienceControllerRunCount";
static NSString *const iTermLaunchExperienceControllerTipOfTheDayEligibilityBeganTime = @"NoSyncTipOfTheDayEligibilityBeganTime";

typedef NS_ENUM(NSUInteger, iTermLaunchExperienceChoice) {
    iTermLaunchExperienceChoiceNone,
    iTermLaunchExperienceChoiceDefaultPasteBehaviorChangeWarning,
    iTermLaunchExperienceChoiceWhatsNew,
    iTermLaunchExperienceChoiceTipOfTheDay,
};

@implementation iTermLaunchExperienceController {
    iTermOnboardingWindowController *_whatsNewInThisVersion;
    iTermLaunchExperienceChoice _choice;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (void)applicationDidFinishLaunching {
    [[self sharedInstance] applicationDidFinishLaunching];
}

+ (void)applicationWillFinishLaunching {
    [[self sharedInstance] applicationWillFinishLaunching];
}

+ (void)performStartupActivities {
    [[self sharedInstance] performStartupActivities];
}

+ (void)forceShowWhatsNew {
    [[self sharedInstance] showWhatsNewInThisVersion];
}

+ (iTermLaunchExperienceChoice)preferredChoice {
    if ([self willWarnAboutChangeToDefaultPasteBehavior]) {
        // This is important because it is an unsafe change.
        return iTermLaunchExperienceChoiceDefaultPasteBehaviorChangeWarning;
    }
    if ([iTermOnboardingWindowController shouldBeShown]) {
        // This preceeds tip of the day because it's more relevant to an upgrading user.
        return iTermLaunchExperienceChoiceWhatsNew;
    }
    if ([[iTermTipController sharedInstance] willAskPermission]) {
        // This is just a nice thing to have.
        return iTermLaunchExperienceChoiceTipOfTheDay;
    }
    return iTermLaunchExperienceChoiceNone;
}

+ (void)quellAnnoyancesForDays:(NSInteger)days {
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate] + days * 24 * 60 * 60
                                              forKey:iTermLaunchExperienceControllerNextAnnoyanceTime];
}

+ (BOOL)quelled {
    const NSTimeInterval quelledUntil = [[NSUserDefaults standardUserDefaults] doubleForKey:iTermLaunchExperienceControllerNextAnnoyanceTime];
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return quelledUntil > now;
}

+ (NSInteger)runCount {
    return [[NSUserDefaults standardUserDefaults] integerForKey:iTermLaunchExperienceControllerRunCount];
}

// Returns the number of times the app has launched since iTermLaunchExperienceController was
// invented (or first install of 3.3+), including the current launch.
+ (NSInteger)incrementRunCount {
    const NSInteger runCount = [self runCount] + 1;
    [[NSUserDefaults standardUserDefaults] setInteger:runCount
                                               forKey:iTermLaunchExperienceControllerRunCount];
    if (runCount == 1) {
        // This is our only chance to get the last launch version.
        if (![iTermOnboardingWindowController previousLaunchVersionImpliesShouldBeShown]) {
            [iTermOnboardingWindowController suppressFutureShowings];
        }
    }
    return runCount;
}

#pragma mark - Instance Methods

- (instancetype)init {
    self = [super init];
    if (self) {
        const NSInteger runCount = [iTermLaunchExperienceController incrementRunCount];
        if (runCount == 2 && ![[SUUpdater sharedUpdater] automaticallyChecksForUpdates]) {
            // Sparkle will do its thing this launch.
            _choice = iTermLaunchExperienceChoiceNone;
        } else if ([iTermLaunchExperienceController quelled]) {
            // Do nothing, we're quelled.
            _choice = iTermLaunchExperienceChoiceNone;
        } else {
            // Normal code path.
            _choice = [iTermLaunchExperienceController preferredChoice];
            if (_choice == iTermLaunchExperienceChoiceTipOfTheDay &&
                ![[NSUserDefaults standardUserDefaults] objectForKey:iTermLaunchExperienceControllerTipOfTheDayEligibilityBeganTime]) {
                [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                                          forKey:iTermLaunchExperienceControllerTipOfTheDayEligibilityBeganTime];
                // The first time we're able to show the tip of the day we'll quell for 2 days so
                // you get a break.
                [iTermLaunchExperienceController quellAnnoyancesForDays:2];
                _choice = iTermLaunchExperienceChoiceNone;
            }
        }
    }
    return self;
}

- (void)performStartupActivities {
    switch (_choice) {
        case iTermLaunchExperienceChoiceTipOfTheDay:
            // Will prompt for access.
            [self.class quellAnnoyancesForDays:1];
            [[iTermTipController sharedInstance] startWithPermissionPromptAllowed:YES notBefore:[NSDate date]];
            return;
        case iTermLaunchExperienceChoiceNone:
            // This is the steady-state.
            [[iTermTipController sharedInstance] startWithPermissionPromptAllowed:NO notBefore:[NSDate date]];
            return;
        case iTermLaunchExperienceChoiceWhatsNew:
        case iTermLaunchExperienceChoiceDefaultPasteBehaviorChangeWarning:
            // If permission was already granted then allow a tip after 24 hours.
            [[iTermTipController sharedInstance] startWithPermissionPromptAllowed:NO
                                                                        notBefore:[NSDate dateWithTimeIntervalSinceNow:24 * 60 * 60]];
            return;
    }
}

- (void)applicationWillFinishLaunching {
#if !DEBUG
    // This is unconditional because it is so important. It enable software update.
    PFMoveToApplicationsFolderIfNecessary();
#endif
}

- (void)applicationDidFinishLaunching {
    switch (_choice) {
        case iTermLaunchExperienceChoiceDefaultPasteBehaviorChangeWarning:
            [self.class quellAnnoyancesForDays:1];
            [self warnAboutChangeToDefaultPasteBehavior];
            return;

        case iTermLaunchExperienceChoiceTipOfTheDay:
        case iTermLaunchExperienceChoiceNone:
            return;

        case iTermLaunchExperienceChoiceWhatsNew:
            [self.class quellAnnoyancesForDays:1];
            [self showWhatsNewInThisVersion];
            return;
    }
}

- (void)showWhatsNewInThisVersion {
    if (!_whatsNewInThisVersion) {
        _whatsNewInThisVersion = [[iTermOnboardingWindowController alloc] initWithWindowNibName:@"iTermOnboardingWindowController"];
    }
    [_whatsNewInThisVersion.window makeKeyAndOrderFront:nil];
    [_whatsNewInThisVersion.window center];
}

+ (BOOL)willWarnAboutChangeToDefaultPasteBehavior {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kHaveWarnedAboutPasteConfirmationChange]) {
        return NO;
    }
    NSString *identifier = [iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey];
    if ([iTermWarning identifierIsSilenced:identifier]) {
        return NO;
    }

    NSArray *warningList = @[ @"3.0.0", @"3.0.1", @"3.0.2", @"3.0.3", @"3.0.4", @"3.0.5", @"3.0.6", @"3.0.7", @"3.0.8", @"3.0.9", @"3.0.10" ];
    if ([warningList containsObject:[iTermPreferences appVersionBeforeThisLaunch]]) {
        return YES;
    }
    return NO;
}

- (void)warnAboutChangeToDefaultPasteBehavior {
    [iTermWarning showWarningWithTitle:@"iTerm2 no longer warns before a multi-line paste, unless you are at the shell prompt."
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Important Change"
                                window:nil];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHaveWarnedAboutPasteConfirmationChange];
}

@end
