//
//  iTermScriptsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/18.
//

#import "iTermScriptsMenuController.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptChooser.h"
#import "iTermScriptExporter.h"
#import "iTermScriptHistory.h"
#import "iTermScriptImporter.h"
#import "iTermScriptTemplatePickerWindowController.h"
#import "iTermTuple.h"
#import "iTermSetupCfgParser.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "SCEvents.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermScriptItem {
    NSMutableArray<iTermScriptItem *> *_children;
}

- (instancetype)initFullEnvironmentWithPath:(NSString *)path parent:(nullable iTermScriptItem *)parent {
    self = [self initFileWithPath:path parent:parent];
    if (self) {
        _fullEnvironment = YES;
    }
    return self;
}

- (instancetype)initFileWithPath:(NSString *)path parent:(nullable iTermScriptItem *)parent {
    self = [super init];
    if (self) {
        _path = [path copy];
        _parent = parent;
    }
    return self;
}

- (instancetype)initFolderWithPath:(NSString *)path parent:(nullable iTermScriptItem *)parent {
    self = [super init];
    if (self) {
        _isFolder = YES;
        _path = [path copy];
        _parent = parent;
    }
    return self;
}

- (NSString *)name {
    return _path.lastPathComponent;
}

- (NSComparisonResult)compare:(iTermScriptItem *)other {
    if (_isFolder != other.isFolder) {
        if (_isFolder) {
            return NSOrderedAscending;
        } else {
            return NSOrderedDescending;
        }
    }
    return [self.name localizedCaseInsensitiveCompare:other.name];
}

- (void)addChild:(iTermScriptItem *)child {
    if (!_children) {
        _children = [NSMutableArray array];
    }
    [_children addObject:child];
}

- (BOOL)isAutoLaunchFolderItem {
    if (!_isFolder) {
        // The auto launch folder is a folder
        return NO;
    }
    if (!_parent) {
        // Is root
        return NO;
    }
    if (_parent.parent != nil) {
        // Parent is not root
        return NO;
    }
    if (![self.name isEqualToString:@"AutoLaunch"]) {
        return NO;
    }

    return YES;
}

@end

@interface iTermScriptsMenuController()<NSOpenSavePanelDelegate, SCEventListenerProtocol, NSMenuItemValidation>
@end

@implementation iTermScriptsMenuController {
    NSMenu *_scriptsMenu;
    BOOL _ranAutoLaunchScript;
    SCEvents *_events;
    NSArray<NSString *> *_allScripts;
    BOOL _disableEnumeration;
    BOOL _uvGateLastSeen;
}

- (instancetype)initWithMenu:(NSMenu *)menu {
    self = [super init];
    if (self) {
        _allScripts = [NSMutableArray array];
        _uvGateLastSeen = [iTermAdvancedSettingsModel pythonRuntimeUsesUV];
        _scriptsMenu = menu;
        _events = [[SCEvents alloc] init];
        _events.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scriptsFolderDidChange:)
                                                     name:iTermScriptsFolderDidChange
                                                   object:nil];
        NSString *path = [[NSFileManager defaultManager] scriptsPath];
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        // Reclaim/restore any backup left by an import interrupted mid-replace (crash
        // between move-aside and cleanup), before enumerating the folder for the menu.
        [iTermScriptImporter recoverStaleReplaceBackups];
        [_events startWatchingPaths:@[ path ]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didInstallPythonRuntime:)
                                                     name:iTermPythonRuntimeDownloaderDidInstallRuntimeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(advancedSettingsDidChange:)
                                                     name:iTermAdvancedSettingsDidChange
                                                   object:nil];
    }
    return self;
}

- (void)advancedSettingsDidChange:(NSNotification *)notification {
    // The notification carries no key, and it fires for every advanced setting. Only
    // act when the uv gate itself changed to ON, so an unrelated setting change does
    // not re-walk the scripts tree on the main thread. Enabling the gate mid-session
    // still shows the one-time version-bump heads-up even though -build ran at launch
    // with the gate off.
    const BOOL gate = [iTermAdvancedSettingsModel pythonRuntimeUsesUV];
    if (gate == _uvGateLastSeen) {
        return;
    }
    _uvGateLastSeen = gate;
    // The gate flip changes which runtime the Manage menu item installs/updates.
    [self updateInstallRuntimeMenuItem];
    if (gate) {
        [self maybeWarnAboutUvVersionBumps];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)scriptsFolderDidChange:(NSNotification *)notification {
    _disableEnumeration = NO;
    [_events stopWatchingPaths];
    NSString *path = [[NSFileManager defaultManager] scriptsPath];
    [_events startWatchingPaths:@[ path ]];
    [self build];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    NSString *path = menuItem.identifier;
    const BOOL isRunning = path && !![[iTermScriptHistory sharedInstance] runningEntryWithPath:path];
    menuItem.state = isRunning ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}

- (void)didInstallPythonRuntime:(NSNotification *)notification {
    [self updateInstallRuntimeMenuItem];
}

- (NSInteger)separatorIndex {
    return [_scriptsMenu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj.identifier isEqualToString:@"Separator"];
    }];
}

- (NSArray<NSString *> *)allScriptsFromMenu {
    NSInteger i = [self separatorIndex];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (i != NSNotFound) {
        [self addMenuItemsIn:_scriptsMenu fromIndex:i + 1 toArray:result path:@""];
    }
    return result;
}

- (void)addMenuItemsIn:(NSMenu *)container fromIndex:(NSInteger)fromIndex toArray:(NSMutableArray<NSString *> *)result path:(NSString *)path {
    for (NSInteger i = fromIndex; i < container.itemArray.count; i++) {
        NSMenuItem *item = container.itemArray[i];
        if (item.submenu) {
            [self addMenuItemsIn:item.submenu fromIndex:0 toArray:result path:[path stringByAppendingPathComponent:item.title]];
        } else if (!item.isAlternate) {
            [result addObject:[path stringByAppendingPathComponent:item.title]];
        }
    }
}

- (void)removeMenuItemsAfterSeparator {
    NSInteger i = [self separatorIndex];
    if (i != NSNotFound) {
        i++;
        while (_scriptsMenu.itemArray.count > i) {
            [_scriptsMenu removeItemAtIndex:i];
        }
    }
}

- (void)build {
    [self removeMenuItemsAfterSeparator];
    [self addMenuItemsTo:_scriptsMenu];
    _allScripts = [self allScriptsFromMenu];
    [self maybeWarnAboutUvVersionBumps];
}

// When uv is enabled, warn once (across launch, and permanently silenceable) that
// migrating existing legacy scripts will bump some pinned Python versions that
// python-build-standalone cannot provide (in practice 3.7 -> 3.9). Scripts are
// migrated lazily on launch; this is the up-front heads-up.
- (void)maybeWarnAboutUvVersionBumps {
    // Latch AFTER the gate check but BEFORE the scan, and regardless of whether the scan
    // produces a warning. -build runs on every launch, every SCEvents file event under
    // the Scripts tree, every install, and scriptsFolderDidChange; the tree walk below is
    // a synchronous main-thread recursive scan with a per-entry stat and a setup.cfg
    // parse. Latching only after a non-nil warning (the old behavior) meant the common
    // case (gate on, no pending bumps) re-walked the whole tree on every one of those
    // events. Leaving the gate-off case unlatched preserves the one scan if the user
    // enables uv later in the session.
    static BOOL checkedThisLaunch = NO;
    if (checkedThisLaunch) {
        return;
    }
    if (![iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
        return;
    }
    checkedThisLaunch = YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *scriptsPath = [fm scriptsPathWithoutSpaces];
    // Walk the whole scripts tree (AutoLaunch and any nested folders). Each record keeps
    // the container's path relative to the scripts folder (so Scripts/foo and
    // AutoLaunch/foo do not collide) plus the absolute path and dependencies the
    // eager-upgrade button needs to migrate it.
    NSMutableArray<iTermUvLegacyScript *> *scripts = [NSMutableArray array];
    [self collectLegacyFullEnvironmentScriptsUnder:scriptsPath
                                        scriptsRoot:scriptsPath
                                               into:scripts];
    NSMutableDictionary<NSString *, NSString *> *requested = [NSMutableDictionary dictionary];
    for (iTermUvLegacyScript *script in scripts) {
        requested[script.relativeName] = script.requestedVersion;
    }
    NSString *text = [iTermUvMigration pendingVersionBumpWarningWithRequestedVersionsByScript:requested];
    if (!text) {
        return;
    }
    // A fresh identifier (not the old OK-only NoSyncUvVersionBumpWarning): the action list
    // grew, and iTermWarning stores a silenced choice by index, so reusing the old id would
    // remap a prior "OK" silence onto the new selection 0 ("Upgrade Now") and silently
    // migrate at launch. A new id shows the upgraded dialog once to previously-silenced users.
    //
    // "Upgrade Now" (selection 0) is a one-shot action, not a standing preference. But the
    // silence checkbox remembers whichever action was chosen, so a user who ticks it while
    // clicking "Upgrade Now" would otherwise re-run the migration silently on every launch
    // (and, for scripts that can't migrate, resurface "Upgrade Incomplete" forever). Clear
    // any remembered "Upgrade Now" up front so only a "Not Now" silence persists; the dialog
    // then always reappears for scripts that stayed legacy rather than auto-migrating.
    NSString *const warningIdentifier = @"NoSyncUvVersionBumpWarningV2";
    [iTermWarning unsilenceIdentifier:warningIdentifier ifSelectionEquals:kiTermWarningSelection0];
    const iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:text
                                   actions:@[ @"Upgrade Now", @"Not Now" ]
                                 accessory:nil
                                identifier:warningIdentifier
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:@"Python Version Changes"
                                    window:nil];
    if (selection == kiTermWarningSelection0) {
        [self upgradeBumpedScripts:[iTermUvMigration scriptsNeedingBump:scripts]];
    }
}

// Eagerly migrate the force-bumped legacy scripts to uv, instead of waiting for each to
// be launched. Scripts are migrated one at a time (a shared runtime download the first
// needs is reused by the rest) behind one progress window; each failure rolls back to its
// working legacy env and is collected for a single summary at the end.
- (void)upgradeBumpedScripts:(NSArray<iTermUvLegacyScript *> *)scripts {
    if (scripts.count == 0) {
        return;
    }
    iTermProvisioningProgressWindowController *progress =
        [[iTermProvisioningProgressWindowController alloc] init];
    [self migrateBumpedScripts:scripts
                         index:0
                      progress:progress
                      failures:[NSMutableArray array]];
}

- (void)migrateBumpedScripts:(NSArray<iTermUvLegacyScript *> *)scripts
                       index:(NSUInteger)index
                    progress:(iTermProvisioningProgressWindowController *)progress
                    failures:(NSMutableArray<NSString *> *)failures {
    if (index >= scripts.count) {
        [progress dismiss];
        [self reportBumpUpgradeFailures:failures];
        return;
    }
    iTermUvLegacyScript *script = scripts[index];
    void (^next)(void) = ^{
        [self migrateBumpedScripts:scripts index:index + 1 progress:progress failures:failures];
    };
    if (script.dependencies == nil) {
        // Its setup.cfg dependencies could not be parsed, so migrating would build a
        // broken env (missing packages). Leave it on its legacy runtime, as the launcher
        // does, and report it.
        [failures addObject:script.relativeName];
        next();
        return;
    }
    [[iTermUvProvisioner shared] migrateLegacyScriptToUvWithContainer:script.containerPath
                                              requestedPythonVersion:script.requestedVersion
                                                        dependencies:script.dependencies
                                                provisioningDidBegin:^{
        [progress showWithMessage:[NSString stringWithFormat:@"Upgrading “%@”…", script.relativeName]];
    }
                                                          completion:^(NSError *error) {
        if (error != nil) {
            if ([iTermUvProvisioner isCancelationError:error]) {
                // The user declined the one-time runtime download. Nothing was migrated and
                // the rest would prompt again, so stop the batch quietly.
                [progress dismiss];
                return;
            }
            // A real failure. migrateLegacyScriptToUv already restored the legacy env, so the
            // script still runs; record it and keep going.
            [failures addObject:script.relativeName];
        }
        next();
    }];
}

- (void)reportBumpUpgradeFailures:(NSArray<NSString *> *)failures {
    if (failures.count == 0) {
        // Silent success: the nag is resolved and the progress window already dismissed.
        return;
    }
    NSString *list = [failures componentsJoinedByString:@"\n• "];
    NSString *body = [NSString stringWithFormat:
                      ITLocalize(@"ScriptsMenu_Alert_CouldNotBeUpgradedAndStillUsePrevious_FORMAT",
                                 @"%1$@ could not be upgraded and still use the previous Python runtime. "
                                 @"Each will be upgraded automatically the next time it runs.\n\n• %2$@",
                                 @"Alert title in checkTimers:"),
                      failures.count == 1 ? ITLocalize(@"PYTHON_RUNTIME_ONE_SCRIPT", @"One script", @"Count of scripts: one") : ITLocalize(@"PYTHON_RUNTIME_SOME_SCRIPTS", @"Some scripts", @"Count of scripts: several"), list];
    [iTermWarning showWarningWithTitle:body
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncUvBumpUpgradeIncomplete"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:ITLocalize(@"ScriptsMenu_AlertHeading_UpgradeIncomplete", @"Upgrade Incomplete", @"Alert heading in checkTimers:")
                                window:nil];
}

// Recursively collect legacy full-environment script containers under `root`, recording
// for each its path relative to `scriptsRoot`, its absolute path, its pinned Python
// version, and its dependencies. A directory with a setup.cfg is a container: it is
// recorded (if legacy) and not descended into, so we never walk into .venv/iterm2env or
// a package's own setup.cfg.
- (void)collectLegacyFullEnvironmentScriptsUnder:(NSString *)root
                                     scriptsRoot:(NSString *)scriptsRoot
                                            into:(NSMutableArray<iTermUvLegacyScript *> *)scripts {
    [self collectLegacyFullEnvironmentScriptsUnder:root scriptsRoot:scriptsRoot depth:0 into:scripts];
}

- (void)collectLegacyFullEnvironmentScriptsUnder:(NSString *)root
                                     scriptsRoot:(NSString *)scriptsRoot
                                           depth:(int)depth
                                            into:(NSMutableArray<iTermUvLegacyScript *> *)scripts {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *setupCfg = [root stringByAppendingPathComponent:@"setup.cfg"];
    if ([fm fileExistsAtPath:setupCfg]) {
        // A real script container has setup.cfg AND an environment: iterm2env (legacy),
        // .venv+marker (uv), or saved-iterm2env (a migration killed midway, which the next
        // launch restores and migrates). A bare setup.cfg with no env is NOT a container
        // (e.g. one dropped in the Scripts root, or a package's own setup.cfg); treating it
        // as one used to stop the walk and silently suppress every version-bump warning.
        const iTermScriptRuntimeBackend backend = [iTermScriptRuntime backendForScriptContainer:root];
        const BOOL savedOnly = [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"saved-iterm2env"]];
        const BOOL isContainer = (backend != iTermScriptRuntimeBackendNone) || savedOnly;
        if (isContainer) {
            // Legacy, or saved-only (which restores to legacy and then migrates): both will
            // migrate and possibly force-bump, so both belong in the predictive warning.
            if (backend == iTermScriptRuntimeBackendLegacy || savedOnly) {
                iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:setupCfg];
                // Fall back to the version the env was actually built on when setup.cfg has
                // no parseable pin (absent, or a range like ">=3.7"). legacyEnvironment...
                // reads saved-iterm2env too, so a saved-only container still resolves.
                NSString *version = parser.pythonVersion ?: [iTermScriptRuntime legacyEnvironmentPythonVersionForContainer:root];
                if (version) {
                    NSString *relative = [root substringFromIndex:scriptsRoot.length];
                    relative = [relative stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
                    NSString *name = relative.length ? relative : root.lastPathComponent;
                    // nil dependencies (an unparseable setup.cfg) marks the script as
                    // migratable-only-lazily; the eager-upgrade button skips and reports it.
                    NSArray<NSString *> *dependencies = parser.dependenciesError ? nil : parser.dependencies;
                    [scripts addObject:[[iTermUvLegacyScript alloc] initWithRelativeName:name
                                                                          containerPath:root
                                                                       requestedVersion:version
                                                                           dependencies:dependencies]];
                }
            }
            return;
        }
        // Stray setup.cfg with no environment: fall through and keep recursing.
    }
    // Bound the recursion. Script containers live at most a couple of levels below the
    // Scripts folder; a deeper tree is not ours and not worth walking on the main thread.
    if (depth >= 8) {
        return;
    }
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        NSString *child = [root stringByAppendingPathComponent:name];
        // lstat (does not resolve the final symlink) so we can skip symlinked entries:
        // following them risks a cycle (infinite recursion / stack overflow at every
        // launch) or walking an arbitrarily large tree. Real script folders are not
        // symlinks.
        NSDictionary *attributes = [fm attributesOfItemAtPath:child error:nil];
        if ([attributes.fileType isEqualToString:NSFileTypeDirectory]) {
            [self collectLegacyFullEnvironmentScriptsUnder:child
                                               scriptsRoot:scriptsRoot
                                                     depth:depth + 1
                                                      into:scripts];
        }
    }
}

- (NSArray<iTermScriptItem *> *)scriptItems {
    DLog(@"begin");
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        DLog(@"not homeDirectoryDotDir");
        return @[];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [fm scriptsPath];
    if ([fm fileExistsAtPath:path]) {
        [fm spacelessAppSupportCreatingLink];  // create link if needed
        path = [fm scriptsPathWithoutSpaces];
    }
    iTermScriptItem *root = [[iTermScriptItem alloc] initFolderWithPath:path parent:nil];
    [self populateScriptItem:root
                originalRoot:path
                clockWatcher:[[iTermClockWatcher alloc] initWithMaxTime:8.0]];
    return root.children;
}

- (void)populateScriptItem:(iTermScriptItem *)parentFolderItem
              originalRoot:(NSString *)originalRoot
              clockWatcher:(iTermClockWatcher *)clockWatcher {
    DLog(@"parentFolderItem=%@ originalRoot=%@", parentFolderItem, originalRoot);
    if (_disableEnumeration) {
        return;
    }
    NSString *root = parentFolderItem.path;
    NSDirectoryEnumerator *directoryEnumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:root];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSSet<NSString *> *scriptExtensions = [NSSet setWithArray:@[ @"scpt", @"app", @"py" ]];

    for (NSString *file in directoryEnumerator) {
        if (clockWatcher.reachedMaxTime) {
            iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:ITLocalize(@"ScriptsMenu_Alert_TakingLongTimeToLocateScripts_FORMAT", @"It is taking a long time to locate all scripts under %1$@. Avoid storing many files or using network mounts for the scripts folder.\n\nContinue?", @"Alert title in checkTimers:"), originalRoot]
                                                                         actions:@[ @"Stop", @"Continue"]
                                                                       accessory:nil
                                                                      identifier:@"TakingTooLongToEnumerateScripts"
                                                                     silenceable:kiTermWarningTypePersistent
                                                                         heading:@"Performance Issue"
                                                                          window:nil];
            if (selection == kiTermWarningSelection0) {
                _disableEnumeration = YES;
                [iTermWarning showWarningWithTitle:ITLocalize(@"ScriptsMenu_Alert_SomeScriptsNotAvailable", @"Some scripts will not be available until the app has restarted or you change the scripts folder.", @"Alert title in checkTimers:")
                                                                             actions:@[ @"OK"]
                                                                           accessory:nil
                                                                          identifier:@"TakingTooLongToEnumerateScripts2"
                                                                         silenceable:kiTermWarningTypePersistent
                                                                             heading:@"Scripts Disabled"
                                            window:nil];
                return;
            } else {
                DLog(@"Extend clock watcher maxtime");
                clockWatcher.maxTime = clockWatcher.elapsedTime + 5.0;
            }
        }
        if ([file.lastPathComponent hasPrefix:@"."]) {
            // Skip hidden entries (.DS_Store, and the transient .replacing-* backups the
            // importer creates while replacing a script) so they never appear as broken
            // menu items, and do not descend into hidden directories.
            [directoryEnumerator skipDescendants];
            continue;
        }

        NSString *path = [root stringByAppendingPathComponent:file];
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
        if (isDirectory) {
            [directoryEnumerator skipDescendants];
            if ([workspace isFilePackageAtPath:path] ||
                [iTermAPIScriptLauncher environmentForScript:path
                                                checkForMain:NO
                                               checkForSaved:YES]) {
                [parentFolderItem addChild:[[iTermScriptItem alloc] initFullEnvironmentWithPath:path parent:parentFolderItem]];
                continue;
            }
            iTermScriptItem *folderItem = [[iTermScriptItem alloc] initFolderWithPath:path parent:parentFolderItem];
            [self populateScriptItem:folderItem originalRoot:originalRoot clockWatcher:clockWatcher];
            if (_disableEnumeration) {
                return;
            }
            if (folderItem.children.count > 0) {
                [parentFolderItem addChild:folderItem];
            }
        } else if ([scriptExtensions containsObject:[file pathExtension]]) {
            [parentFolderItem addChild:[[iTermScriptItem alloc] initFileWithPath:path parent:parentFolderItem]];
        } else if ([file.pathExtension isEqualToString:@"its"]) {
            [self didFindScriptArchive:path autolaunch:parentFolderItem.isAutoLaunchFolderItem];
        }
    }
}

- (void)didFindScriptArchive:(NSString *)file autolaunch:(BOOL)autolaunch {
    RLog(@"didFindScriptArchive:%@ autolaunch:%@", file, @(autolaunch));
    static NSMutableSet<NSString *> *alreadyFound;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        alreadyFound = [NSMutableSet set];
    });
    if ([alreadyFound containsObject:file]) {
        return;
    }
    [alreadyFound addObject:file];
    // "Move to Trash" should not be remembered - silently trashing future
    // script archives without prompting would be surprising.
    iTermWarning *warning = [[iTermWarning alloc] init];
    warning.title = [NSString stringWithFormat:ITLocalize(@"ScriptsMenu_WarningTitle_ScriptArchiveFoundInScriptsDirectory_FORMAT", @"A script archive named “%1$@” was found in the Scripts directory. Would you like to install it?", @"Warning title in scanForScriptArchives"), file.lastPathComponent];
    warning.actionLabels = @[ @"OK", @"Cancel", ITLocalize(@"ScriptsMenu_Action_MoveToTrash", @"Move to Trash", @"Button title in scanForScriptArchives") ];
    warning.identifier = @"NoSyncInstallScriptArchive";
    warning.warningType = kiTermWarningTypeTemporarilySilenceable;
    warning.heading = ITLocalize(@"ScriptsMenu_AlertHeading_InstallScriptArchive", @"Install Script Archive?", @"Alert heading in scanForScriptArchives");
    warning.doNotRememberLabels = @[ ITLocalize(@"ScriptsMenu_Action_MoveToTrash", @"Move to Trash", @"Button title in scanForScriptArchives"), @"Cancel" ];
    const iTermWarningSelection selection = [warning runModal];
    NSURL *url = [NSURL fileURLWithPath:file];
    switch (selection) {
        case kiTermWarningSelection0: {
            if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
                break;
            }
            DLog(@"Import from %@", url);
            [iTermScriptImporter importScriptFromURL:url
                                       userInitiated:YES
                                     offerAutoLaunch:autolaunch
                                       callbackQueue:dispatch_get_main_queue()
                                             avoidUI:NO
                                          completion:^(NSString * _Nullable errorMessage, BOOL quiet, NSURL *location) {
                DLog(@"Completed with %@", errorMessage);
                if (quiet) {
                    return;
                }
                if (errorMessage == nil) {
                    [[NSFileManager defaultManager] trashItemAtURL:url
                                                  resultingItemURL:nil
                                                             error:nil];
                }
                [self importDidFinishWithErrorMessage:errorMessage
                                             location:location
                                          originalURL:url];
            }];
            break;
        }
        case kiTermWarningSelection1:
            break;
        case kiTermWarningSelection2:
            [[NSFileManager defaultManager] trashItemAtURL:url
                                          resultingItemURL:nil
                                                     error:nil];
        default:
            break;
    }
}

- (void)addMenuItemsTo:(NSMenu *)rootMenu {
    [self addMenuItemsForScriptItems:[self scriptItems]
                              toMenu:rootMenu];
}

- (void)addMenuItemsForScriptItems:(NSArray<iTermScriptItem *> *)unsortedScriptItems
                            toMenu:(NSMenu *)containingMenu {
    NSArray<iTermScriptItem *> *const scriptItems = [unsortedScriptItems sortedArrayUsingSelector:@selector(compare:)];
    for (iTermScriptItem *scriptItem in scriptItems) {
        if (scriptItem.isFolder) {
            NSMenuItem *submenuItem = [[NSMenuItem alloc] init];
            submenuItem.title = scriptItem.name;
            submenuItem.submenu = [[NSMenu alloc] initWithTitle:scriptItem.name];
            [containingMenu addItem:submenuItem];
            [self addMenuItemsForScriptItems:scriptItem.children toMenu:submenuItem.submenu];
            continue;
        }

        [self addFile:scriptItem.name withFullPath:scriptItem.path toScriptMenu:containingMenu];
    }
}

- (BOOL)runAutoLaunchScriptsIfNeeded {
    if (self.shouldRunAutoLaunchScripts) {
        [self runAutoLaunchScripts];
        return YES;
    } else {
        DLog(@"Not running auto-launch scripts");
        _ranAutoLaunchScript = YES;
        return NO;
    }
}

- (void)revealScriptsInFinder {
    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];

    [[NSFileManager defaultManager] createDirectoryAtPath:scriptsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSWorkspace sharedWorkspace] it_revealInFinder:scriptsPath];
}

- (void)setInstallRuntimeMenuItem:(NSMenuItem *)installRuntimeMenuItem {
    _installRuntimeMenuItem = installRuntimeMenuItem;
    [self updateInstallRuntimeMenuItem];
}

// The one place that titles/targets the Scripts > Manage runtime menu item, routed
// through the gate so it never updates the wrong runtime. Called when the outlet is set,
// after a uv/legacy install, and when the gate flips.
- (void)updateInstallRuntimeMenuItem {
    if (!_installRuntimeMenuItem) {
        return;
    }
    const iTermPythonRuntimeMenuAction action =
        [iTermScriptRuntime pythonRuntimeMenuActionWithUvGateEnabled:[iTermAdvancedSettingsModel pythonRuntimeUsesUV]
                                                         uvInstalled:[iTermUvProvisioner isInstalled]
                                                     legacyInstalled:[[iTermPythonRuntimeDownloader sharedInstance] isPythonRuntimeInstalled]];
    _installRuntimeMenuItem.title = [iTermScriptRuntime pythonRuntimeMenuItemTitleFor:action];
    if (action == iTermPythonRuntimeMenuActionLegacyCheckForUpdate) {
        // Only the legacy check-for-update targets the legacy downloader directly.
        _installRuntimeMenuItem.action = @selector(userRequestedCheckForUpdate);
        _installRuntimeMenuItem.target = [iTermPythonRuntimeDownloader sharedInstance];
    } else {
        // uv install, uv check-for-update, and legacy install all route to the app
        // delegate's installPythonRuntime: (a XIB-wired IBAction with no header, so
        // resolve the selector at runtime), with a nil target so it goes up the
        // responder chain to the app delegate.
        _installRuntimeMenuItem.action = NSSelectorFromString(@"installPythonRuntime:");
        _installRuntimeMenuItem.target = nil;
    }
}

- (void)chooseAndExportScript {
    NSString *autoLaunchPath = [[[NSFileManager defaultManager] autolaunchScriptPath] stringByResolvingSymlinksInPath];
    [iTermScriptChooser chooseMultipleWithValidator:
     ^BOOL(NSURL *url) {
        return [url.path.stringByResolvingSymlinksInPath isEqualToString:autoLaunchPath] || [iTermScriptExporter urlIsScript:url];
    }
                                autoLaunchByDefault:NO
                                         completion:
     ^(NSArray<NSURL *> *urls, SIGIdentity *signingIdentity, BOOL autolaunch) {
        if (!urls) {
            return;
        }
        for (NSURL *url in urls) {
            [iTermScriptExporter exportScriptAtURL:url
                                   signingIdentity:signingIdentity
                                     callbackQueue:dispatch_get_main_queue()
                                       destination:nil
                                        autolaunch:autolaunch
                                        completion:^(NSString *errorMessage, NSURL *zipURL) {
                if (errorMessage || !zipURL) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = ITLocalize(@"ScriptsMenu_Alert_ExportFailed", @"Export Failed", @"Alert title in exportDidFinish");
                    alert.informativeText = errorMessage ?: ITLocalize(@"ScriptsMenu_AlertExplanatory_FailedToCreateArchive", @"Failed to create archive", @"Alert explanatory text in exportDidFinish");
                    [alert runModal];
                    return;
                }

                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ zipURL ]];
            }];
        }
    }];
}

- (void)chooseAndImportScript {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    DLog(@"begin");
    iTermOpenPanel *panel = [[iTermOpenPanel alloc] init];
    panel.allowedContentTypes = @[ UTTypeZIP, [UTType typeWithFilenameExtension:@"its"], UTTypePythonScript ];
    panel.allowsMultipleSelection = YES;
    panel.preferredSSHIdentity = [SSHIdentity localhost];
    [panel beginWithFallback:^(NSModalResponse response, NSArray<NSURL *> *urls) {
        if (response == NSModalResponseOK) {
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSURL *url in urls) {
                    [self importFromURL:url];
                }
            });
        }
    }];
}

- (void)importFromURL:(NSURL *)url {
    DLog(@"%@", url);
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        DLog(@"Not homeDirectoryDotDir");
        return;
    }
    [iTermScriptImporter importScriptFromURL:url
                               userInitiated:YES
                             offerAutoLaunch:NO
                               callbackQueue:dispatch_get_main_queue()
                                     avoidUI:NO
                                  completion:^(NSString * _Nullable errorMessage, BOOL quiet, NSURL *location) {
        DLog(@"%@", errorMessage);
        // Mojave deadlocks if you do this without the dispatch_async
        dispatch_async(dispatch_get_main_queue(), ^{
            if (quiet) {
                return;
            }
            [self importDidFinishWithErrorMessage:errorMessage
                                         location:location
                                      originalURL:url];
        });
    }];
}

- (void)importDidFinishWithErrorMessage:(nullable NSString *)errorMessage
                               location:(NSURL *)location
                            originalURL:(NSURL *)url {
    RLog(@"error=%@ location=%@ url=%@", errorMessage, location, url);
    if (errorMessage) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = ITLocalize(@"ScriptsMenu_Alert_CouldNotInstallScript", @"Could Not Install Script", @"Alert title in importDidFinishWithErrorMessage:(nullable NSString *)errorMessage");
        alert.informativeText = errorMessage;
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:ITLocalize(@"ScriptsMenu_Button_TryAgain", @"Try Again", @"Button title in importDidFinishWithErrorMessage:(nullable NSString *)errorMessage")];
        if ([alert runModal] ==  NSAlertSecondButtonReturn) {
            [self importFromURL:url];
        }
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = ITLocalize(@"ScriptsMenu_Alert_ScriptImportedSuccessfully", @"Script Imported Successfully", @"Alert title in importDidFinishWithErrorMessage:(nullable NSString *)errorMessage");
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:ITLocalize(@"ScriptsMenu_Button_Launch", @"Launch", @"Button title in importDidFinishWithErrorMessage:(nullable NSString *)errorMessage")];
        const NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            return;
        }
        if (response == NSAlertSecondButtonReturn) {
            [self launchScriptWithAbsolutePath:location.path
                                     arguments:@[]
                            explicitUserAction:YES];
        }
    }
}

- (BOOL)scriptShouldAutoLaunchWithFullPath:(NSString *)fullPath {
    return [fullPath hasPrefix:[[iTermScriptsMenuController autolaunchScriptPath] stringByAppendingString:@"/"]];
}

- (NSString *)autoLaunchPathIfFullPathWereMovedToAutoLaunch:(NSString *)fullPath {
    return [[iTermScriptsMenuController autolaunchScriptPath] stringByAppendingPathComponent:fullPath.lastPathComponent];
}

- (BOOL)couldMoveScriptToAutoLaunch:(NSString *)fullPath {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return NO;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:[iTermScriptsMenuController autolaunchScriptPath]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[iTermScriptsMenuController autolaunchScriptPath]]) {
        return NO;
    }

    NSString *destination = [self autoLaunchPathIfFullPathWereMovedToAutoLaunch:fullPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destination]) {
        return NO;
    }
    return YES;
}

- (void)moveScriptToAutoLaunch:(NSString *)fullPath {
    [[NSFileManager defaultManager] createDirectoryAtPath:[iTermScriptsMenuController autolaunchScriptPath]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *destination = [self autoLaunchPathIfFullPathWereMovedToAutoLaunch:fullPath];
    [[NSFileManager defaultManager] moveItemAtPath:fullPath
                                            toPath:destination error:nil];
}

#pragma mark - Actions

- (void)launchOrTerminateScript:(NSMenuItem *)sender {
    NSString *fullPath = sender.identifier;
    DLog(@"%@", fullPath);
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] runningEntryWithPath:fullPath];
    if (entry) {
        [entry kill];
    } else {
        [self launchScriptWithAbsolutePath:fullPath
                                 arguments:@[]
                        explicitUserAction:YES];
    }
}

- (void)revealScript:(NSMenuItem *)sender {
    NSString *identifier = sender.identifier;
    NSString *prefix = @"/Reveal/";
    NSString *fullPath = [identifier substringFromIndex:prefix.length];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:fullPath] ]];
}

- (void)launchScriptWithRelativePath:(NSString *)path
                           arguments:(NSArray<NSString *> *)arguments
                  explicitUserAction:(BOOL)explicitUserAction {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return;
    }
    NSString *fullPath = [[[NSFileManager defaultManager] scriptsPathWithoutSpaces] stringByAppendingPathComponent:path];
    DLog(@"fullPath=%@ args=%@ explicitUserAction=%@", fullPath, arguments, @(explicitUserAction));
    [self launchScriptWithAbsolutePath:fullPath
                             arguments:arguments
                    explicitUserAction:explicitUserAction];
}

// NOTE: This logic needs to be kept in sync with -couldLaunchScriptWithAbsolutePath
- (void)launchScriptWithAbsolutePath:(NSString *)fullPath
                           arguments:(NSArray<NSString *> *)arguments
                  explicitUserAction:(BOOL)explicitUserAction {
    RLog(@"launch path=%@ args=%@", fullPath, RLogRedact(arguments, @(arguments.count)));
    // If handed the inner main.py of a full-environment script (Foo/Foo/Foo.py) rather
    // than its container (Foo), resolve to the container. This happens when the script is
    // launched from a stale index (e.g. Open Quickly built before the environment was
    // provisioned) or by its .py path directly; without this it would launch as a basic
    // script on the shared standard runtime and miss its own dependencies. Issue: a full
    // env script imported and then launched too soon showed ModuleNotFoundError.
    NSString *fullEnvContainer = [iTermAPIScriptLauncher fullEnvironmentContainerForMainPyPath:fullPath];
    if (fullEnvContainer) {
        RLog(@"Redirecting main.py launch to full-environment container %@", fullEnvContainer);
        fullPath = fullEnvContainer;
    }
    NSString *venv = [iTermAPIScriptLauncher environmentForScript:fullPath
                                                     checkForMain:YES
                                                    checkForSaved:YES];
    if (venv) {
        if (!explicitUserAction && ![iTermAPIHelper isEnabled]) {
            RLog(@"Not launching %@ because the API is not enabled", fullPath);
            return;
        }
        if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
            return;
        }
        NSString *name = fullPath.lastPathComponent;
        NSString *mainPyPath = [[[fullPath stringByAppendingPathComponent:name] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"py"];
        [iTermAPIScriptLauncher launchScript:mainPyPath
                                    fullPath:fullPath
                                   arguments:arguments
                              withVirtualEnv:venv
                                setupCfgPath:[fullPath stringByAppendingPathComponent:@"setup.cfg"]
                          explicitUserAction:explicitUserAction];
        return;
    }

    // A uv script whose interpreter is gone (the shared uv runtime was deleted to reclaim
    // disk, or the home dir was renamed): the marker + setup.cfg are intact but
    // .venv/bin/python no longer resolves, so environmentForScript returned nil. The
    // script is NOT malformed; its runtime went missing, and setup.cfg can rebuild it.
    if ([self uvScriptContainerNeedsReprovision:fullPath]) {
        if (explicitUserAction) {
            // An explicit launch offers to rebuild, then runs it.
            [self offerToReprovisionUvScript:fullPath arguments:arguments explicitUserAction:explicitUserAction];
        } else {
            // AutoLaunch / non-explicit at startup: do not pop a consent dialog + progress
            // window (there could be several such scripts). Log the real cause and the
            // recovery gesture to the Script Console instead of the generic malformed modal.
            NSString *line = [NSString stringWithFormat:@"The Python environment for “%@” is missing (the shared runtime may have been deleted). Launch it from the Scripts menu to rebuild it.\n",
                              fullPath.lastPathComponent];
            [[iTermScriptHistoryEntry globalEntry] addOutput:line completion:^{}];
            RLog(@"uv script %@ needs reprovision; not offering at non-explicit launch", fullPath);
        }
        return;
    }

    if ([[fullPath pathExtension] isEqualToString:@"py"]) {
        if (!explicitUserAction && ![iTermAPIHelper isEnabled]) {
            RLog(@"Not launching %@ because the API is not enabled", fullPath);
            return;
        }
        if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
            return;
        }
        [iTermAPIScriptLauncher launchScript:fullPath
                                   arguments:arguments
                          explicitUserAction:explicitUserAction];
        return;
    }
    if ([[fullPath pathExtension] isEqualToString:@"scpt"]) {
        NSURL *aURL = [NSURL fileURLWithPath:fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];
        NSError *error = nil;
        NSUserAppleScriptTask *script = [[NSUserAppleScriptTask alloc] initWithURL:aURL error:&error];
        if (!script) {
            [self showAlertForScript:fullPath error:error];
            return;
        }
        [script executeWithAppleEvent:nil completionHandler:^(NSAppleEventDescriptor * _Nullable result, NSError * _Nullable error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showAlertForScript:fullPath error:error];
                });
            }
        }];
        return;
    }
    if ([[NSFileManager defaultManager] itemIsDirectory:fullPath]) {
        // "Reveal" is a one-time Finder action and shouldn't be remembered.
        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.title = [NSString stringWithFormat:ITLocalize(@"ScriptsMenu_WarningTitle_MalformedScript_FORMAT", @"The script “%1$@” is malformed.", @"Warning title in runScriptItem:"), fullPath.lastPathComponent];
        warning.actionLabels = @[ @"OK", ITLocalize(@"ScriptsMenu_Action_Reveal", @"Reveal", @"Button title in runScriptItem:") ];
        warning.identifier = @"NoSyncScriptMalformed";
        warning.warningType = kiTermWarningTypeTemporarilySilenceable;
        warning.heading = ITLocalize(@"ScriptsMenu_AlertHeading_CannotRunScript", @"Cannot Run Script", @"Alert heading in runScriptItem:");
        warning.doNotRememberLabels = @[ ITLocalize(@"ScriptsMenu_Action_Reveal", @"Reveal", @"Button title in runScriptItem:") ];
        iTermWarningSelection selection = [warning runModal];
        if (selection == kiTermWarningSelection1) {
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:fullPath] ]];
            return;
        }
        return;
    }
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:fullPath]
                                          configuration:[NSWorkspaceOpenConfiguration configuration]
                                      completionHandler:nil];
}

// A uv full-environment script that has lost its interpreter: the python-runtime.json
// marker and setup.cfg are present, but .venv/bin/python (a symlink into the shared uv
// python dir) no longer resolves. This happens if the shared uv directory was deleted, the
// home dir was renamed, or the Scripts folder was restored onto another machine.
- (BOOL)uvScriptContainerNeedsReprovision:(NSString *)container {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *marker = [container stringByAppendingPathComponent:[iTermScriptRuntime markerFileName]];
    NSString *setupCfg = [container stringByAppendingPathComponent:@"setup.cfg"];
    NSString *interpreter = [[container stringByAppendingPathComponent:[iTermScriptRuntime venvDirectoryName]]
                             stringByAppendingPathComponent:@"bin/python"];
    return [fm fileExistsAtPath:marker] &&
           [fm fileExistsAtPath:setupCfg] &&
           ![fm fileExistsAtPath:interpreter];  // follows the symlink: false if it dangles
}

- (void)offerToReprovisionUvScript:(NSString *)container
                         arguments:(NSArray<NSString *> *)arguments
                explicitUserAction:(BOOL)explicitUserAction {
    NSString *name = container.lastPathComponent;
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:ITLocalize(@"ScriptsMenu_Alert_PythonEnvironmentForScriptMissing_FORMAT", @"The Python environment for “%1$@” is missing (the shared runtime may have been deleted). Rebuild it from its saved requirements now?", @"Alert title in uvScriptContainerNeedsReprovision:"), name]
                               actions:@[ ITLocalize(@"ScriptsMenu_Action_Rebuild", @"Rebuild", @"Action title in uvScriptContainerNeedsReprovision:"), @"Cancel" ]
                             accessory:nil
                            identifier:@"NoSyncRebuildMissingUvEnv"
                           silenceable:kiTermWarningTypePersistent
                               heading:ITLocalize(@"ScriptsMenu_AlertHeading_RebuildPythonEnvironment", @"Rebuild Python Environment?", @"Alert heading in uvScriptContainerNeedsReprovision:")
                                window:nil];
    if (selection != kiTermWarningSelection0) {
        return;
    }
    NSString *setupCfgPath = [container stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:setupCfgPath];
    NSArray<NSString *> *dependencies = parser.dependencies ?: @[];
    // Prefer the version the marker recorded (what it actually ran), then the setup.cfg pin,
    // then the default. createSetupCfg:NO so the existing setup.cfg is preserved.
    NSString *version = [iTermScriptRuntime pythonVersionForScriptContainer:container]
        ?: parser.pythonVersion
        ?: [iTermScriptRuntime defaultPythonVersion];
    __block iTermProvisioningProgressWindowController *progress = [[iTermProvisioningProgressWindowController alloc] init];
    __weak __typeof(self) weakSelf = self;
    [[iTermUvProvisioner shared] downloadAndProvisionFullEnvironmentWithContainer:container
                                                          requestedPythonVersion:version
                                                                    dependencies:dependencies
                                                                  createSetupCfg:NO
                                                            provisioningDidBegin:^{
        [progress showWithMessage:ITLocalize(@"ScriptsMenu_Status_RebuildingPythonEnvironment", @"Rebuilding the Python environment…", @"Status message in uvScriptContainerNeedsReprovision:")];
    }
                                                                      completion:^(NSError *error) {
        [progress dismiss];
        progress = nil;
        if (error != nil) {
            if (![iTermUvProvisioner isCancelationError:error]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = ITLocalize(@"ScriptsMenu_Alert_CouldNotRebuildEnvironment", @"Could Not Rebuild Environment", @"Alert title in uvScriptContainerNeedsReprovision:");
                alert.informativeText = error.localizedDescription ?: ITLocalize(@"ScriptsMenu_UnknownError", @"Unknown error", @"Fallback error text in uvScriptContainerNeedsReprovision:");
                [alert runModal];
            }
            return;
        }
        // Rebuilt: launch it now.
        [weakSelf launchScriptWithAbsolutePath:container
                                     arguments:arguments
                            explicitUserAction:explicitUserAction];
    }];
}

// NOTE: This logic needs to be kept in sync with -launchScriptWithAbsolutePath
- (BOOL)couldLaunchScriptWithAbsolutePath:(NSString *)fullPath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return NO;
    }
    NSString *venv = [iTermAPIScriptLauncher environmentForScript:fullPath
                                                     checkForMain:YES
                                                    checkForSaved:YES];
    if (venv) {
        return YES;
    }
    // A uv script whose interpreter went missing has no resolvable venv, but an explicit
    // launch (e.g. the status bar component's "Launch Script" recovery button) offers to
    // rebuild it, so it IS launchable. Keep this in sync with launchScriptWithAbsolutePath.
    if ([self uvScriptContainerNeedsReprovision:fullPath]) {
        return YES;
    }

    if ([[fullPath pathExtension] isEqualToString:@"py"]) {
        return YES;
    }
    if ([[fullPath pathExtension] isEqualToString:@"scpt"]) {
        NSAppleScript *script;
        NSDictionary *errorInfo = nil;
        NSURL *aURL = [NSURL fileURLWithPath:fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        script = [[NSAppleScript alloc] initWithContentsOfURL:aURL error:&errorInfo];
        return script != nil;
    } else {
        return NO;
    }
}

- (NSString *)pathToTemplateForPicker:(iTermScriptTemplatePickerWindowController *)picker {
    NSArray<NSString *> *environmentNamePart = @[ @"na", @"basic", @"pyenv" ];
    NSArray<NSString *> *templateNamePart = @[ @"na", @"simple", @"daemon" ];
    NSString *templateName = [NSString stringWithFormat:@"template_%@_%@",
                              environmentNamePart[picker.selectedEnvironment],
                              templateNamePart[picker.selectedTemplate]];
    NSString *templatePath = [[NSBundle bundleForClass:self.class] pathForResource:templateName ofType:@"py"];
    return templatePath;
}

- (void)newPythonScript {
    DLog(@"begin");
    if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
        // With uv there is no shared runtime to pre-download; a full-environment
        // script is provisioned per-script during creation, and a basic script needs
        // nothing at creation time.
        [self reallyCreateNewPythonScript];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    iTermPythonRuntimeDownloader *downloader = [iTermPythonRuntimeDownloader sharedInstance];
    [downloader downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                     pythonVersion:nil
                                         minimumEnvironmentVersion:0
                                                requiredToContinue:YES
                                                    withCompletion:^(iTermPythonRuntimeDownloaderStatus status) {
        DLog(@"status=%@", @(status));
        switch (status) {
            case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
            case iTermPythonRuntimeDownloaderStatusCanceledByUser:
            case iTermPythonRuntimeDownloaderStatusUnknown:
            case iTermPythonRuntimeDownloaderStatusWorking:
            case iTermPythonRuntimeDownloaderStatusError:
                return;
            case iTermPythonRuntimeDownloaderStatusNotNeeded:
            case iTermPythonRuntimeDownloaderStatusDownloaded:
                break;
        }
        [weakSelf reallyCreateNewPythonScript];
    }];
}

- (void)reallyCreateNewPythonScript {
    DLog(@"begin");
    iTermScriptTemplatePickerWindowController *picker = [[iTermScriptTemplatePickerWindowController alloc] initWithWindowNibName:@"iTermScriptTemplatePickerWindowController"];
    [NSApp runModalForWindow:picker.window];
    [picker.window close];

    if (picker.selectedEnvironment == iTermScriptEnvironmentNone ||
        picker.selectedTemplate == iTermScriptTemplateNone) {
        DLog(@"no env/template");
        return;
    }

    NSArray<NSString *> *dependencies = nil;
    NSString *pythonVersion = nil;
    NSURL *url = [self runSavePanelForNewScriptWithPicker:picker dependencies:&dependencies pythonVersion:&pythonVersion];
    DLog(@"%@", url);
    if (!url) {
        return;
    }
    if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
        // No legacy runtime download under uv; provisioning happens per-script below.
        [self reallyCreateNewPythonScriptAtURL:url picker:picker dependencies:dependencies pythonVersion:pythonVersion];
        return;
    }
    {
        [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                            pythonVersion:pythonVersion
                                                                                minimumEnvironmentVersion:0
                                                                                       requiredToContinue:YES
                                                                                           withCompletion:
         ^(iTermPythonRuntimeDownloaderStatus status) {
            DLog(@"status=%@", @(status));
             switch (status) {
                 case iTermPythonRuntimeDownloaderStatusRequestedVersionNotFound:
                 case iTermPythonRuntimeDownloaderStatusCanceledByUser:
                 case iTermPythonRuntimeDownloaderStatusUnknown:
                 case iTermPythonRuntimeDownloaderStatusWorking:
                 case iTermPythonRuntimeDownloaderStatusError: {
                     return;
                 }

                 case iTermPythonRuntimeDownloaderStatusNotNeeded:
                 case iTermPythonRuntimeDownloaderStatusDownloaded:
                     break;
             }
             [self reallyCreateNewPythonScriptAtURL:url picker:picker dependencies:dependencies pythonVersion:pythonVersion];
        }];
    }
}

- (void)reallyCreateNewPythonScriptAtURL:(NSURL *)url
                                  picker:(iTermScriptTemplatePickerWindowController *)picker
                            dependencies:(NSArray<NSString *> *)dependencies
                           pythonVersion:(nullable NSString *)pythonVersion {
    RLog(@"url=%@ deps=%@ pythonVersion=%@ selectedEnvironment=%@", url, dependencies, pythonVersion, @(picker.selectedEnvironment));
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        NSURL *folder = [NSURL fileURLWithPath:[self folderForFullEnvironmentSavePanelURL:url]];
        __block iTermProvisioningProgressWindowController *progress = nil;
        void (^installCompletion)(NSError *) = ^(NSError *errorStatus) {
            [progress dismiss];
            progress = nil;
            if (errorStatus != nil) {
                 if ([iTermUvProvisioner isCancelationError:errorStatus]) {
                     // The user declined the download; do not report a failure.
                     return;
                 }
                 NSAlert *alert = [[NSAlert alloc] init];
                 alert.messageText = ITLocalize(@"ScriptsMenu_Alert_InstallationFailed", @"Installation Failed", @"Alert title in installPythonRuntimeForPicker:error:");
                 if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
                     alert.informativeText = [NSString stringWithFormat:ITLocalize(@"ScriptsMenu_AlertExplanatory_ErrorOccurredCreatingEnvironment_FORMAT", @"An error occurred while creating the Python environment. The error was: %1$@", @"Alert explanatory text in installPythonRuntimeForPicker:error:"), errorStatus.localizedDescription];
                 } else {
                     alert.informativeText = [NSString stringWithFormat:ITLocalize(@"ScriptsMenu_AlertExplanatory_ErrorOccurredInstallingRuntime_FORMAT", @"An error ocurred while installing the Python runtime. Remove ~/Library/Application Support/iTerm2/iterm2env and try again. The error was: %1$@", @"Alert explanatory text in installPythonRuntimeForPicker:error:"), errorStatus.localizedDescription];
                 }
                 [alert runModal];
                 return;
             }
             [self finishInstallingNewPythonScriptForPicker:picker url:url];
             [self build];
        };
        if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
            progress = [[iTermProvisioningProgressWindowController alloc] init];
            // Show progress only once the download phase is done and the venv build
            // starts, so it does not float over the download confirmation and progress
            // window.
            [[iTermUvProvisioner shared] downloadAndProvisionFullEnvironmentWithContainer:folder.path
                                                                  requestedPythonVersion:pythonVersion ?: [iTermScriptRuntime defaultPythonVersion]
                                                                            dependencies:dependencies ?: @[]
                                                                          createSetupCfg:YES
                                                                    provisioningDidBegin:^{
                [progress showWithMessage:@"Setting up the Python environment…"];
            }
                                                                              completion:installCompletion];
        } else {
            NSURL *existingEnv = [folder URLByAppendingPathComponent:@"iterm2env"];
            [[NSFileManager defaultManager] removeItemAtURL:existingEnv error:nil];
            [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:folder
                                                                         dependencies:dependencies
                                                                        pythonVersion:pythonVersion
                                                                           completion:installCompletion];
        }
    } else {
        [self finishInstallingNewPythonScriptForPicker:picker url:url];
    }
}

- (void)finishInstallingNewPythonScriptForPicker:(iTermScriptTemplatePickerWindowController *)picker
                                             url:(NSURL *)url  {
    // destinationTemplatePath is a full path to the main.py file, e.g. foo/bar/bar/bar.py
    NSString *destinationTemplatePath = [self destinationTemplatePathForPicker:picker url:url];
    NSString *template = [self templateForPicker:picker url:url];
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[url.path stringByAppendingPathComponent:url.path.lastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    [template writeToURL:[NSURL fileURLWithPath:destinationTemplatePath]
              atomically:NO
                encoding:NSUTF8StringEncoding
                   error:nil];
    NSString *app = nil;
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:[NSURL fileURLWithPath:destinationTemplatePath]];
    if (appURL) {
        app = [[NSFileManager defaultManager] displayNameAtPath:appURL.path];
    }
    if (app) {
        // "Show in Finder" is a one-time navigation action and shouldn't be remembered.
        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.title = [NSString stringWithFormat:ITLocalize(@"ScriptsMenu_WarningTitle_OpenNewScriptIn_FORMAT", @"Open new script in %1$@?", @"Warning title in createTemplateFromPicker:"), app];
        warning.actionLabels = @[ @"OK", ITLocalize(@"ScriptsMenu_Action_ShowInFinder", @"Show in Finder", @"Button title in createTemplateFromPicker:") ];
        warning.identifier = @"NoSyncOpenNewPythonScriptInDefaultEditor";
        warning.warningType = kiTermWarningTypePermanentlySilenceable;
        warning.doNotRememberLabels = @[ ITLocalize(@"ScriptsMenu_Action_ShowInFinder", @"Show in Finder", @"Button title in createTemplateFromPicker:") ];
        iTermWarningSelection selection = [warning runModal];
        if (selection == kiTermWarningSelection0) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:destinationTemplatePath]];
            return;
        }
    }
    [[NSWorkspace sharedWorkspace] selectFile:destinationTemplatePath inFileViewerRootedAtPath:@""];
}

- (NSPopUpButton *)newPythonVersionPopup {
    NSPopUpButton *popUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, 0, 50, 50)];

    if ([iTermAdvancedSettingsModel pythonRuntimeUsesUV]) {
        // Offer exactly what the INSTALLED uv can provide (uv python list), never a
        // hardcoded set that an older installed uv might not support. Show the default as
        // a placeholder immediately (the popup must be non-empty when returned), then
        // fill the real list asynchronously. If uv is not installed yet, the default is
        // the only choice and the first provision downloads uv and resolves it.
        NSString *best = [iTermScriptRuntime defaultPythonVersion];
        [popUpButton addItemWithTitle:best];
        [popUpButton selectItemAtIndex:0];
        [[iTermUvProvisioner shared] availableMinorsWithCompletion:^(NSArray<NSString *> *minors) {
            if (minors.count == 0) {
                return;  // uv not installed / query failed: keep the default placeholder.
            }
            NSArray<NSString *> *versions = [minors sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
                return [a compare:b options:NSNumericSearch];
            }];
            [popUpButton.menu removeAllItems];
            for (NSString *version in versions) {
                [popUpButton addItemWithTitle:version];
            }
            // Prefer the default if this uv provides it, else the newest available.
            [popUpButton selectItemWithTitle:best];
            if (popUpButton.indexOfSelectedItem < 0 && popUpButton.numberOfItems > 0) {
                [popUpButton selectItemAtIndex:popUpButton.numberOfItems - 1];
            }
        }];
        return popUpButton;
    }

    NSArray<NSString *> *components = @[ @"iterm2env", @"versions" ];
    NSString *path = [[NSFileManager defaultManager] spacelessAppSupportCreatingLink];
    for (NSString *part in components) {
        path = [path stringByAppendingPathComponent:part];
    }
    NSString *best = [iTermPythonRuntimeDownloader bestPythonVersionAt:path];
    NSMenuItem *defaultMenuItem = nil;
    for (NSString *pythonVersion in [iTermPythonRuntimeDownloader pythonVersionsAt:path]) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:pythonVersion action:NULL keyEquivalent:@""];
        if ([pythonVersion isEqualToString:best]) {
            defaultMenuItem = menuItem;
        }
        [popUpButton.menu addItem:menuItem];
    }
    if (defaultMenuItem) {
        [popUpButton selectItem:defaultMenuItem];
    }
    return popUpButton;
}

- (NSTokenField *)newTokenFieldForDependencies {
    NSTokenField *tokenField = [[NSTokenField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
    tokenField.tokenizingCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    tokenField.placeholderString = ITLocalize(@"ScriptsMenu_Placeholder_PackageNames", @"Package names", @"Placeholder text for the package names token field");
    tokenField.font = [NSFont systemFontOfSize:13];
    return tokenField;
}

- (NSView *)newAccessoryViewForSavePanelWithTokenField:(NSTokenField *)tokenField
                                    pythonVersionPopup:(NSPopUpButton *)pythonVersionPopup {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 60, 22)];
    [label setEditable:NO];
    [label setStringValue:ITLocalize(@"ScriptsMenu_Label_PyPIDependencies", @"PyPI Dependencies:", @"Label for the PyPI dependencies field")];
    label.font = [NSFont systemFontOfSize:13];
    [label setBordered:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label sizeToFit];

    NSTextField *pythonVersionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 60, 22)];
    [pythonVersionLabel setEditable:NO];
    [pythonVersionLabel setStringValue:@"Python Version:"];
    pythonVersionLabel.font = [NSFont systemFontOfSize:13];
    [pythonVersionLabel setBordered:NO];
    [pythonVersionLabel setBezeled:NO];
    [pythonVersionLabel setDrawsBackground:NO];
    [pythonVersionLabel sizeToFit];

    const CGFloat tokenFieldWidth = 300;
    const CGFloat margin = 9;
    NSView  *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSMaxX(tokenField.frame) + margin + tokenFieldWidth, 32)];
    [accessoryView addSubview:label];
    [accessoryView addSubview:pythonVersionLabel];
    [accessoryView addSubview:tokenField];
    [accessoryView addSubview:pythonVersionPopup];
    tokenField.frame = NSMakeRect(NSMaxX(label.frame) + margin, 5, tokenFieldWidth, 22);

    accessoryView.translatesAutoresizingMaskIntoConstraints = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    pythonVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    tokenField.translatesAutoresizingMaskIntoConstraints = NO;
    pythonVersionPopup.translatesAutoresizingMaskIntoConstraints = NO;

    const CGFloat sideMargin = 9;
    const CGFloat verticalMargin = 5;
    NSDictionary *views = @{ @"label": label,
                             @"pythonVersionLabel": pythonVersionLabel,
                             @"tokenField": tokenField,
                             @"pythonVersionPopup": pythonVersionPopup };
    NSDictionary *metrics = @{ @"sideMargin": @(sideMargin),
                               @"verticalMargin": @(verticalMargin) };
    [accessoryView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-sideMargin-[label]"
                                                                          options:0
                                                                          metrics:metrics
                                                                            views:views]];
    [accessoryView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[tokenField]-sideMargin-|"
                                                                          options:0
                                                                          metrics:metrics
                                                                            views:views]];
    [accessoryView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-sideMargin-[pythonVersionLabel]"
                                                                          options:0
                                                                          metrics:metrics
                                                                            views:views]];
    [accessoryView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-verticalMargin-[label]-verticalMargin-[pythonVersionPopup]-verticalMargin-|"
                                                                          options:0
                                                                          metrics:metrics
                                                                            views:views]];

    // tokenField.leading >= label.trailing + 5
    [accessoryView addConstraint:[NSLayoutConstraint constraintWithItem:tokenField
                                                              attribute:NSLayoutAttributeLeading
                                                              relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                 toItem:label
                                                              attribute:NSLayoutAttributeTrailing
                                                             multiplier:1
                                                               constant:5]];
    // pythonVersionPopup.trailing >= pythonVersionLabel.trailing + 5
    [accessoryView addConstraint:[NSLayoutConstraint constraintWithItem:pythonVersionPopup
                                                              attribute:NSLayoutAttributeLeading
                                                              relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                                 toItem:pythonVersionLabel
                                                              attribute:NSLayoutAttributeTrailing
                                                             multiplier:1
                                                               constant:5]];
    [pythonVersionPopup setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [tokenField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    // tokenField.baseline = label.basline
    [accessoryView addConstraint:[NSLayoutConstraint constraintWithItem:tokenField
                                                              attribute:NSLayoutAttributeBaseline
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:label
                                                              attribute:NSLayoutAttributeBaseline
                                                             multiplier:1
                                                               constant:0]];
    // pythonVersionPopup.leading = tokenField.leading
    [accessoryView addConstraint:[NSLayoutConstraint constraintWithItem:pythonVersionPopup
                                                              attribute:NSLayoutAttributeLeading
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:tokenField
                                                              attribute:NSLayoutAttributeLeading
                                                             multiplier:1
                                                               constant:0]];

    // Make the token field want to be as wide as possible.
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:tokenField
                                                                  attribute:NSLayoutAttributeWidth
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:accessoryView
                                                                  attribute:NSLayoutAttributeWidth
                                                                 multiplier:1
                                                                   constant:0];
    constraint.priority = NSLayoutPriorityDefaultLow;
    [accessoryView addConstraint:constraint];
    return accessoryView;
}

- (nullable NSURL *)runSavePanelForNewScriptWithPicker:(iTermScriptTemplatePickerWindowController *)picker
                                          dependencies:(out NSArray<NSString *> **)dependencies
                                         pythonVersion:(out NSString **)pythonVersionOut {
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.delegate = self;
    NSTokenField *tokenField = nil;
    NSPopUpButton *pythonVersionPopup = nil;
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        savePanel.allowedContentTypes = @[ UTTypeFolder ];
        tokenField = [self newTokenFieldForDependencies];
        pythonVersionPopup = [self newPythonVersionPopup];
        savePanel.accessoryView = [self newAccessoryViewForSavePanelWithTokenField:tokenField
                                                                pythonVersionPopup:pythonVersionPopup];
    } else {
        savePanel.allowedContentTypes = @[ UTTypePythonScript ];
    }
    savePanel.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];

    if ([savePanel runModal] == NSModalResponseOK) {
        NSURL *url = savePanel.URL;
        NSString *filename = [url lastPathComponent];
        NSString *safeFilename = [filename stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        if ([filename isEqualToString:safeFilename]) {
            *dependencies = tokenField.objectValue;
            *pythonVersionOut = pythonVersionPopup.selectedItem.title;
            return url;
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = ITLocalize(@"ScriptsMenu_Alert_SpacesNotAllowed", @"Spaces Not Allowed", @"Alert title in addFile:withFullPath:");
            alert.informativeText = ITLocalize(@"ScriptsMenu_AlertExplanatory_ScriptsCantHaveSpaceCharacters", @"Scripts can't have space characters in their filenames.", @"Alert explanatory text in addFile:withFullPath:");
            [alert addButtonWithTitle:ITLocalize(@"ScriptsMenu_Action_UseInsteadOfSpace", @"Use _ Instead of Space", @"Action title in addFile:withFullPath:")];
            [alert addButtonWithTitle:ITLocalize(@"ScriptsMenu_Action_ChangeName", @"Change Name", @"Action title in addFile:withFullPath:")];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:safeFilename];
            } else {
                return [self runSavePanelForNewScriptWithPicker:picker
                                                   dependencies:dependencies
                                                  pythonVersion:pythonVersionOut];
            }
        }
    } else {
        return nil;
    }
}
- (NSString *)templateForPicker:(iTermScriptTemplatePickerWindowController *)picker
                            url:(NSURL *)url {
    NSString *pythonVersion = [self pythonVersionForPicker:picker url:url];
    NSDictionary *subs = @{ @"$$PYTHON_VERSION$$": pythonVersion ?: @"3" };
    NSString *templatePath = [self pathToTemplateForPicker:picker];
    NSMutableString *template = [NSMutableString stringWithContentsOfFile:templatePath
                                                                 encoding:NSUTF8StringEncoding
                                                                    error:nil];
    [subs enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [template replaceOccurrencesOfString:key withString:obj options:0 range:NSMakeRange(0, template.length)];
    }];
    return template;
}

- (NSString *)relativePathFrom:(NSString *)possibleSuper toPath:(NSString *)possibleSub {
    return [self relativePathFrom:possibleSuper toPath:possibleSub relative:@""];
}

- (nullable NSString *)relativePathFrom:(NSString *)possibleSuper toPath:(NSString *)possibleSub relative:(NSString *)relative {
    if (possibleSub.length < possibleSuper.length) {
        return nil;
    }
    if ([possibleSub isEqualToString:possibleSuper]) {
        return relative;
    }
    return [self relativePathFrom:possibleSuper
                           toPath:[possibleSub stringByDeletingLastPathComponent]
                         relative:[possibleSub.lastPathComponent stringByAppendingPathComponent:relative]];
}

- (NSString *)folderForFullEnvironmentSavePanelURL:(NSURL *)url {
    NSString *noSpacesScriptsRoot = [[NSFileManager defaultManager] scriptsPathWithoutSpaces];
    NSString *scriptsRoot = [[[NSURL fileURLWithPath:noSpacesScriptsRoot] URLByResolvingSymlinksInPath] path];
    NSString *selectedPath = [url URLByResolvingSymlinksInPath].path;
    NSString *relative = [self relativePathFrom:scriptsRoot
                                         toPath:selectedPath];
    if (relative) {
        return [noSpacesScriptsRoot stringByAppendingPathComponent:relative];
    } else {
        NSString *name = url.path.lastPathComponent;
        NSString *folder = [noSpacesScriptsRoot stringByAppendingPathComponent:name];
        return folder;
    }
}

- (NSString *)destinationTemplatePathForPicker:(iTermScriptTemplatePickerWindowController *)picker
                                           url:(NSURL *)url {
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        NSString *folder = [self folderForFullEnvironmentSavePanelURL:url];
        NSString *name = url.path.lastPathComponent;
        // For a path like foo/bar this returns foo/bar/bar/bar.py
        // So the hierarchy looks like
        // ~/Library/ApplicationSupport/iTerm2/Scripts/foo/bar/setup.cfg
        // ~/Library/ApplicationSupport/iTerm2/Scripts/foo/bar/iterm2env
        // ~/Library/ApplicationSupport/iTerm2/Scripts/foo/bar/bar/
        // ~/Library/ApplicationSupport/iTerm2/Scripts/foo/bar/bar/bar.py
        return [[folder stringByAppendingPathComponent:name] stringByAppendingPathComponent:[url.path.lastPathComponent stringByAppendingPathExtension:@"py"]];
    } else {
        return url.path;
    }
}

// Returns a string like "3.10".
- (NSString * _Nullable)pythonVersionForPicker:(iTermScriptTemplatePickerWindowController *)picker
                                           url:(NSURL *)url {
    NSString *raw;
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        NSString *path = [iTermAPIScriptLauncher pathToVersionsFolderForPyenvScriptNamed:url.lastPathComponent];
        raw = [iTermPythonRuntimeDownloader bestPythonVersionAt:path];
    } else {
        raw = [iTermPythonRuntimeDownloader latestPythonVersion];
    }
    if (!raw) {
        return nil;
    }
    return [[[raw componentsSeparatedByString:@"."] subarrayToIndex:2] componentsJoinedByString:@"."];
}

#pragma mark - Private

- (void)addFile:(NSString *)file withFullPath:(NSString *)path toScriptMenu:(NSMenu *)scriptMenu {
    NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:file
                                                        action:@selector(launchOrTerminateScript:)
                                                 keyEquivalent:@""];

    [scriptItem setTarget:self];
    scriptItem.identifier = path;
    [scriptMenu addItem:scriptItem];

    NSMenuItem *altItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Reveal %@", file]
                                                        action:@selector(revealScript:)
                                                 keyEquivalent:@""];

    [altItem setKeyEquivalentModifierMask:NSEventModifierFlagOption];
    [altItem setTarget:self];
    altItem.alternate = YES;
    altItem.identifier = [NSString stringWithFormat:@"/Reveal/%@", path];
    [scriptMenu addItem:altItem];
}

- (void)showAlertForScript:(NSString *)fullPath error:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = ITLocalize(@"ScriptsMenu_Alert_ProblemRunningScript", @"Problem running script", @"Alert title in showAlertForScript:error:");
    alert.informativeText = [NSString stringWithFormat:@"The script at “%@” failed:\n\n%@",
                             fullPath, error.localizedFailureReason];
    [alert runModal];
}

+ (NSString *)autolaunchScriptPath {
    return [[NSFileManager defaultManager] autolaunchScriptPath];
}

+ (NSString *)legacyAutolaunchScriptPath {
    return [[NSFileManager defaultManager] legacyAutolaunchScriptPath];
}

+ (BOOL)autoLaunchFolderExists {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        DLog(@"Not homeDirectoryDotDir");
        return NO;
    }
    return ([[NSFileManager defaultManager] fileExistsAtPath:iTermScriptsMenuController.legacyAutolaunchScriptPath] ||
            [[NSFileManager defaultManager] fileExistsAtPath:iTermScriptsMenuController.autolaunchScriptPath]);
}

- (BOOL)shouldRunAutoLaunchScripts {
    if (_ranAutoLaunchScript) {
        DLog(@"Already ran");
        return NO;
    }
    return [iTermScriptsMenuController autoLaunchFolderExists];
}

- (void)runAutoLaunchScripts {
    DLog(@"run auto launch scripts");
    _ranAutoLaunchScript = YES;

    [self runLegacyAutoLaunchScripts];
    [self runModernAutoLaunchScripts];
}

- (void)runModernAutoLaunchScripts {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        DLog(@"Not homeDirectoryDotDir");
        return;
    }
    NSString *scriptsPath = [[NSFileManager defaultManager] autolaunchScriptPath];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:scriptsPath];
    for (NSString *file in enumerator) {
        DLog(@"%@", file);
        if ([file hasPrefix:@"."]) {
            continue;
        }
        if ([file.lastPathComponent isEqualToString:@"__pycache__"]) {
            // Python drops a __pycache__ directory next to single-file
            // scripts. It is not a script, so skip it silently instead of
            // warning that it is malformed.
            [enumerator skipDescendants];
            continue;
        }
        NSString *path = [scriptsPath stringByAppendingPathComponent:file];
        if ([[NSFileManager defaultManager] itemIsDirectory:path]) {
            [enumerator skipDescendants];
        }
        [self runAutoLaunchScript:path];
    }
}

- (void)runAutoLaunchScript:(NSString *)path {
    DLog(@"%@", path);
    [self launchScriptWithAbsolutePath:path arguments:@[] explicitUserAction:NO];
}

- (void)runLegacyAutoLaunchScripts {
    NSURL *aURL = [NSURL fileURLWithPath:iTermScriptsMenuController.legacyAutolaunchScriptPath];

    // Make sure our script suite registry is loaded
    [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

    NSError *error = nil;
    NSUserAppleScriptTask *script = [[NSUserAppleScriptTask alloc] initWithURL:aURL error:&error];
    if (!script) {
        return;
    }
    DLog(@"Execute %@", aURL);
    [script executeWithAppleEvent:nil completionHandler:nil];
}

#pragma mark - SCEventListenerProtocol

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event {
    if ([[iTermPythonRuntimeDownloader sharedInstance] busy] ||
        [iTermUvProvisioner isProvisioningFullEnvironment]) {
        // A uv .venv build under Scripts/<name>/ emits thousands of file events; do not
        // rebuild the menu for each. build runs once at the provision's completion.
        return;
    }
    DLog(@"Path watcher noticed a change to scripts directory");
    [self build];
}

#pragma mark - NSOpenSavePanelDelegate

- (BOOL)urlIsUnderScripts:(NSURL *)folder {
    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];
    return ([folder.path isEqualToString:scriptsPath] ||
            [folder.path hasPrefix:[scriptsPath stringByAppendingString:@"/"]]);
}

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    return [self urlIsUnderScripts:url];
}

- (void)panel:(NSSavePanel *)sender didChangeToDirectoryURL:(nullable NSURL *)url {
    if (![self urlIsUnderScripts:url]) {
        sender.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];
    }
}

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
    if ([self urlIsUnderScripts:url]) {
        return YES;
    }
    NSString *message = [NSString stringWithFormat:@"Full-environment scripts must be located under in your Application Support/iTerm2/Scripts directory:\n%@", [[NSFileManager defaultManager] scriptsPath]];
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"FullEnvironmentScriptsLocationRestricted"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Invalid Folder"
                                window:sender];
    return NO;
}

@end

NS_ASSUME_NONNULL_END
