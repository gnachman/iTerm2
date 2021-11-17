//
//  iTermRecordingCodec.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/8/18.
//

#import "iTermRecordingCodec.h"
#import "iTermController.h"
#import "iTermSavePanel.h"
#import "iTermSessionLauncher.h"
#import "iTermWarning.h"
#import "NSData+iTerm.h"
#import "NSData+GZIP.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"

@implementation iTermRecordingCodec

+ (void)loadRecording {
    NSOpenPanel *panel = [[NSOpenPanel alloc] init];
    panel.allowedFileTypes = @[ @"itr" ];
    if ([panel runModal] == NSModalResponseOK) {
        [self loadRecording:panel.URL];
    }
}

+ (void)loadRecording:(NSURL *)url {
    NSError *error = nil;
    NSData *gzipped = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!gzipped) {
        [iTermWarning showWarningWithTitle:error.localizedDescription ?: @"Unknown error"
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"RecordingMalformed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Could not read the file: its envelope was malformed."
                                    window:nil];
        return;
    }

    NSData *data = [gzipped gunzippedData];
    if (!data) {
        [iTermWarning showWarningWithTitle:@"Could not read the file: decompression failed."
                                   actions:@[ @"OK" ]
                                identifier:@"RecordingMalformed"
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
        return;
    }
    // I don't know why, but if you only give it a dictionary it fails to
    // decode. I find it hard to believe that keyed unarchiver would still have
    // a bug like this, but I can't come up with a better explanation :(
    NSDictionary *dict = [data it_unarchivedObjectOfClasses:@[ [NSDictionary class], [NSArray class] ]];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        [iTermWarning showWarningWithTitle:@"Could not read the file: unarchiving decompressed data failed."
                                   actions:@[ @"OK" ]
                                identifier:@"RecordingMalformed"
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
        return;
    }

    NSArray<NSNumber *> *supportedVersions = @[ @1, @2, @3 ];
    if (![supportedVersions containsObject:dict[@"version"]]) {
        [iTermWarning showWarningWithTitle:@"This recording is from a newer version of iTerm2 and cannot be replayed in this version."
                                   actions:@[ @"OK" ]
                             actionMapping:nil
                                 accessory:nil
                                identifier:@"RecordingMalformed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Can’t Load Recording"
                                    window:nil];
        return;
    }

    NSDictionary *dvrDict = dict[@"dvr"];
    Profile *dictProfile = dict[@"profile"];
    if (!dvrDict || !dictProfile) {
        [iTermWarning showWarningWithTitle:@"This recording could not be loaded because it is missing critical information."
                                   actions:@[ @"OK" ]
                             actionMapping:nil
                                 accessory:nil
                                identifier:@"RecordingMalformed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Can’t Load Recording"
                                    window:nil];
        return;
    }

    if (![iTermSessionLauncher profileIsWellFormed:dictProfile]) {
        return;
    }

    [iTermSessionLauncher launchBookmark:dictProfile
                              inTerminal:nil
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:^(NSDictionary *profile, PseudoTerminal *windowController, void (^makeSessionCompletion)(PTYSession *)) {
        PTYSession *newSession = [[PTYSession alloc] initSynthetic:YES];
        newSession.profile = profile;
        [newSession.screen.dvr loadDictionary:dvrDict];
        [windowController setupSession:newSession withSize:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [windowController replaySession:newSession];
        });
        [windowController insertSession:newSession atIndex:0];
        makeSessionCompletion(newSession);
    }
                          didMakeSession:nil
                              completion:nil];
}

+ (void)exportRecording:(PTYSession *)session window:(NSWindow *)window {
    [self exportRecording:session
                     from:session.screen.dvr.firstTimeStamp
                       to:session.screen.dvr.lastTimeStamp
                   window:window];
}

+ (void)exportRecording:(PTYSession *)session from:(long long)from to:(long long)to window:(NSWindow *)window {
    iTermSavePanel *savePanel = [iTermSavePanel showWithOptions:0
                                                     identifier:@"ExportRecording"
                                               initialDirectory:NSHomeDirectory()
                                                defaultFilename:@"Recording.itr"
                                               allowedFileTypes:@[ @"itr" ]
                                                         window:window];
    if (savePanel.path) {
        NSURL *url = [NSURL fileURLWithPath:savePanel.path];
        if (url) {
            NSDictionary *dvrDict = [session.screen.dvr dictionaryValueFrom:from to:to];
            if (dvrDict) {
                NSMutableDictionary *profile = [session.profile ?: @{} mutableCopy];
                // Remove any private info that isn't visible.
                [profile removeObjectForKey:KEY_NAME];
                [profile removeObjectForKey:KEY_COMMAND_LINE];
                [profile removeObjectsForKeys:@[ KEY_NAME, KEY_COMMAND_LINE, KEY_WORKING_DIRECTORY, KEY_AUTOLOG,
                                                 KEY_LOGGING_STYLE, KEY_DESCRIPTION,
                                                 KEY_INITIAL_TEXT, KEY_TAGS, KEY_TITLE_COMPONENTS,
                                                 KEY_ORIGINAL_GUID,
                                                 KEY_AWDS_WIN_DIRECTORY, KEY_AWDS_TAB_DIRECTORY,
                                                 KEY_AWDS_PANE_DIRECTORY, KEY_LOGDIR, KEY_LOG_FILENAME_FORMAT, KEY_SHOW_STATUS_BAR,
                                                 KEY_STATUS_BAR_LAYOUT, KEY_HAS_HOTKEY, KEY_TRIGGERS, KEY_TRIGGERS_USE_INTERPOLATED_STRINGS,
                                                 KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS,
                                                 KEY_SMART_SELECTION_RULES, KEY_SEMANTIC_HISTORY,
                                                 KEY_BOUND_HOSTS, KEY_DYNAMIC_PROFILE_PARENT_NAME,
                                                 KEY_DYNAMIC_PROFILE_PARENT_GUID,
                                                 KEY_DYNAMIC_PROFILE_FILENAME ]];

                // Make sure the GUID doesn't match an existing one.
                profile[KEY_GUID] = [[NSUUID UUID] UUIDString];

                // Version 2 added per-line metadata.
                // Version 3 moved URL codes into external attributes.
                NSDictionary *dict = @{ @"dvr": dvrDict,
                                        @"profile": profile,
                                        @"version": @3 };
                
                NSData *dictData = [[NSData it_dataWithArchivedObject:dict] gzippedData];
                NSError *error = nil;
                BOOL ok = [dictData writeToURL:url options:0 error:&error];
                if (!ok) {
                    [iTermWarning showWarningWithTitle:error.localizedDescription
                                               actions:@[ @"OK" ]
                                             accessory:nil
                                            identifier:@"ErrorSavingRecording"
                                           silenceable:kiTermWarningTypePersistent
                                               heading:@"The recording could not be saved."
                                                window:nil];
                }
            } else {
                [iTermWarning showWarningWithTitle:@"Error encoding recording."
                                           actions:@[ @"OK" ]
                                        identifier:@"ErrorSavingRecording"
                                       silenceable:kiTermWarningTypePersistent
                                            window:nil];
            }
        }
    }
}

@end
