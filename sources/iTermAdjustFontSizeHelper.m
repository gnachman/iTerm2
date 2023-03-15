//
//  iTermAdjustFontSizeHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/16/18.
//

#import "iTermAdjustFontSizeHelper.h"

#import "iTerm2SharedARC-Swift.h"
#import "ITAddressBookMgr.h"
#import "NSFont+iTerm.h"
#import "PTYSession.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermPreferences.h"

@implementation iTermAdjustFontSizeHelper

+ (void)biggerFont:(PTYSession *)currentSession {
    if ([iTermPreferences boolForKey:kPreferenceKeySizeChangesAffectProfile]) {
        [self adjustProfileFontSizeBy:1];
    } else {
        [self adjustFontSizeBy:1];
    }
}

+ (void)smallerFont:(PTYSession *)currentSession {
    if ([iTermPreferences boolForKey:kPreferenceKeySizeChangesAffectProfile]) {
        [self adjustProfileFontSizeBy:-1];
    } else {
        [self adjustFontSizeBy:-1];
    }
}

+ (void)toggleSizeChangesAffectProfile {
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceKeySizeChangesAffectProfile] forKey:kPreferenceKeySizeChangesAffectProfile];
}

+ (void)returnToDefaultSize:(PTYSession *)currentSession resetRowsCols:(BOOL)reset {
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    PTYSession *session = [frontTerminal currentSession];
    if (!reset) {
        for (PTYSession *session in [self sessionsToAdjustFontSize]) {
            [session changeFontSizeDirection:0];
        }
    } else {
        [session changeFontSizeDirection:0];
    }
    if (reset) {
        NSDictionary *abEntry = [session originalProfile];
        [frontTerminal sessionInitiatedResize:session
                                        width:MIN(iTermMaxInitialSessionSize,
                                                  [[abEntry objectForKey:KEY_COLUMNS] intValue])
                                       height:MIN(iTermMaxInitialSessionSize,
                                                  [[abEntry objectForKey:KEY_ROWS] intValue])];
    }
}

+ (NSArray<PTYSession *> *)sessionsToAdjustFontSize {
    PTYSession *session = [[[iTermController sharedInstance] currentTerminal] currentSession];
    if (!session) {
        return nil;
    }
    if ([iTermAdvancedSettingsModel fontChangeAffectsBroadcastingSessions]) {
        NSArray<PTYSession *> *broadcastSessions = [[[iTermController sharedInstance] currentTerminal] broadcastSessions];
        if ([broadcastSessions containsObject:session]) {
            return broadcastSessions;
        }
    }
    return @[ session ];
}

+ (void)adjustFontSizeBy:(int)delta {
    for (PTYSession *session in [self sessionsToAdjustFontSize]) {
        [session changeFontSizeDirection:delta];
    }
}

+ (void)adjustProfileFontSizeBy:(int)delta {
    [self adjustFontSizeBy:delta];
    NSMutableSet<NSString *> *guids = [NSMutableSet set];
    for (PTYSession *session in [self sessionsToAdjustFontSize]) {
        NSString *guid = session.profile[KEY_ORIGINAL_GUID];
        if (guid) {
            [guids addObject:guid];
        }
        guid = session.profile[KEY_GUID];
        if (guid) {
            [guids addObject:guid];
        }
    }
    for (NSString *guid in guids) {
        MutableProfile *profile = [[[ProfileModel sharedInstance] bookmarkWithGuid:guid] mutableCopy];
        if (profile) {
            iTermFontTable *fontTable = [[iTermFontTable fontTableForProfile:profile] fontTableGrownBy:delta];
            profile[KEY_NORMAL_FONT] = fontTable.asciiFont.font.stringValue;
            profile[KEY_NON_ASCII_FONT] = fontTable.defaultNonASCIIFont.font.stringValue;
            profile[KEY_FONT_CONFIG] = fontTable.configString;
            [[ProfileModel sharedInstance] setBookmark:profile withGuid:guid];
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                        object:nil
                                                      userInfo:nil];
    
    // Update user defaults
    [[NSUserDefaults standardUserDefaults] setObject:[[ProfileModel sharedInstance] rawData]
                                              forKey: @"New Bookmarks"];
}

@end
