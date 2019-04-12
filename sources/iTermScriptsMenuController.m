//
//  iTermScriptsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/18.
//

#import "iTermScriptsMenuController.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBuildingScriptWindowController.h"
#import "iTermCommandRunner.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptChooser.h"
#import "iTermScriptExporter.h"
#import "iTermScriptHistory.h"
#import "iTermScriptImporter.h"
#import "iTermScriptTemplatePickerWindowController.h"
#import "iTermTuple.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
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

@end

@interface iTermScriptsMenuController()<NSOpenSavePanelDelegate, SCEventListenerProtocol>
@end

@implementation iTermScriptsMenuController {
    NSMenu *_scriptsMenu;
    BOOL _ranAutoLaunchScript;
    SCEvents *_events;
    NSArray<NSString *> *_allScripts;
    NSInteger _disablePathWatcher;
}

- (instancetype)initWithMenu:(NSMenu *)menu {
    self = [super init];
    if (self) {
        _allScripts = [NSMutableArray array];
        _scriptsMenu = menu;
        _events = [[SCEvents alloc] init];
        _events.delegate = self;
        NSString *path = [[NSFileManager defaultManager] scriptsPath];
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        [_events startWatchingPaths:@[ path ]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didInstallPythonRuntime:)
                                                     name:iTermPythonRuntimeDownloaderDidInstallRuntimeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    NSString *path = menuItem.identifier;
    const BOOL isRunning = path && !![[iTermScriptHistory sharedInstance] runningEntryWithPath:path];
    menuItem.state = isRunning ? NSOnState : NSOffState;
    return YES;
}

- (void)didInstallPythonRuntime:(NSNotification *)notification {
    [self changeInstallToUpdate];
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
}

+ (NSArray<iTermScriptItem *> *)scriptItems {
    iTermScriptItem *root = [[iTermScriptItem alloc] initFolderWithPath:[[NSFileManager defaultManager] scriptsPathWithoutSpaces] parent:nil];
    [self populateScriptItem:root];
    return root.children;
}

+ (void)populateScriptItem:(iTermScriptItem *)parentFolderItem {
    NSString *root = parentFolderItem.path;
    NSDirectoryEnumerator *directoryEnumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:root];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSSet<NSString *> *scriptExtensions = [NSSet setWithArray:@[ @"scpt", @"app", @"py" ]];

    for (NSString *file in directoryEnumerator) {
        if ([file caseInsensitiveCompare:@".DS_Store"] == NSOrderedSame) {
            continue;
        }

        NSString *path = [root stringByAppendingPathComponent:file];
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
        if (isDirectory) {
            [directoryEnumerator skipDescendents];
            if ([workspace isFilePackageAtPath:path] ||
                [iTermAPIScriptLauncher environmentForScript:path checkForMain:NO]) {
                [parentFolderItem addChild:[[iTermScriptItem alloc] initFullEnvironmentWithPath:path parent:parentFolderItem]];
                continue;
            }
            iTermScriptItem *folderItem = [[iTermScriptItem alloc] initFolderWithPath:path parent:parentFolderItem];
            [self populateScriptItem:folderItem];
            if (folderItem.children.count > 0) {
                [parentFolderItem addChild:folderItem];
            }
        } else if ([scriptExtensions containsObject:[file pathExtension]]) {
            [parentFolderItem addChild:[[iTermScriptItem alloc] initFileWithPath:path parent:parentFolderItem]];
        }
    }
}

- (void)addMenuItemsTo:(NSMenu *)rootMenu {
    [self addMenuItemsForScriptItems:[iTermScriptsMenuController scriptItems]
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
    [[NSWorkspace sharedWorkspace] openFile:scriptsPath withApplication:@"Finder"];
}

- (void)setInstallRuntimeMenuItem:(NSMenuItem *)installRuntimeMenuItem {
    _installRuntimeMenuItem = installRuntimeMenuItem;
    if ([[iTermPythonRuntimeDownloader sharedInstance] isPythonRuntimeInstalled]) {
        [self changeInstallToUpdate];
    }
}

- (void)changeInstallToUpdate {
    _installRuntimeMenuItem.title = @"Check for Updated Runtime";
    _installRuntimeMenuItem.action = @selector(userRequestedCheckForUpdate);
    _installRuntimeMenuItem.target = [iTermPythonRuntimeDownloader sharedInstance];
}

- (void)chooseAndExportScript {
    [iTermScriptChooser chooseWithValidator:^BOOL(NSURL *url) {
        return [iTermScriptExporter urlIsScript:url];
    } completion:^(NSURL *url, SIGIdentity *signingIdentity) {
        if (!url) {
            return;
        }
        [iTermScriptExporter exportScriptAtURL:url signingIdentity:signingIdentity completion:^(NSString *errorMessage, NSURL *zipURL) {
            if (errorMessage || !zipURL) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Export Failed";
                alert.informativeText = errorMessage ?: @"Failed to create archive";
                [alert runModal];
                return;
            }

            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ zipURL ]];
        }];
    }];
}

- (void)chooseAndImportScript {
    NSOpenPanel *panel = [[NSOpenPanel alloc] init];
    panel.allowedFileTypes = @[ @"zip", @"its" ];
    if ([panel runModal] == NSModalResponseOK) {
        NSURL *url = panel.URL;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self importFromURL:url];
        });
    }
}

- (void)importFromURL:(NSURL *)url {
    [iTermScriptImporter importScriptFromURL:url
                               userInitiated:YES
                                  completion:^(NSString * _Nullable errorMessage, BOOL quiet, NSURL *location) {
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

- (void)importDidFinishWithErrorMessage:(NSString *)errorMessage
                               location:(NSURL *)location
                            originalURL:(NSURL *)url {
    if (errorMessage) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Could Not Install Script";
        alert.informativeText = errorMessage;
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Try Again"];
        if ([alert runModal] ==  NSAlertSecondButtonReturn) {
            [self importFromURL:url];
        }
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Script Imported Successfully";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Launch"];
        const NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            return;
        }
        if (response == NSAlertSecondButtonReturn) {
            [self launchScriptWithAbsolutePath:location.path
                            explicitUserAction:YES];
        }
    }
}

- (BOOL)scriptShouldAutoLaunchWithFullPath:(NSString *)fullPath {
    return [fullPath hasPrefix:[[self autolaunchScriptPath] stringByAppendingString:@"/"]];
}

- (NSString *)autoLaunchPathIfFullPathWereMovedToAutoLaunch:(NSString *)fullPath {
    return [[self autolaunchScriptPath] stringByAppendingPathComponent:fullPath.lastPathComponent];
}

- (BOOL)couldMoveScriptToAutoLaunch:(NSString *)fullPath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return NO;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:[self autolaunchScriptPath]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self autolaunchScriptPath]]) {
        return NO;
    }

    NSString *destination = [self autoLaunchPathIfFullPathWereMovedToAutoLaunch:fullPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destination]) {
        return NO;
    }
    return YES;
}

- (void)moveScriptToAutoLaunch:(NSString *)fullPath {
    [[NSFileManager defaultManager] createDirectoryAtPath:[self autolaunchScriptPath]
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
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] runningEntryWithPath:fullPath];
    if (entry) {
        [entry kill];
    } else {
        [self launchScriptWithAbsolutePath:fullPath explicitUserAction:YES];
    }
}

- (void)revealScript:(NSMenuItem *)sender {
    NSString *identifier = sender.identifier;
    NSString *prefix = @"/Reveal/";
    NSString *fullPath = [identifier substringFromIndex:prefix.length];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:fullPath] ]];
}

- (void)launchScriptWithRelativePath:(NSString *)path
                  explicitUserAction:(BOOL)explicitUserAction {
    NSString *fullPath = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:path];
    [self launchScriptWithAbsolutePath:fullPath explicitUserAction:explicitUserAction];
}

// NOTE: This logic needs to be kept in sync with -couldLaunchScriptWithAbsolutePath
- (void)launchScriptWithAbsolutePath:(NSString *)fullPath explicitUserAction:(BOOL)explicitUserAction {
    NSString *venv = [iTermAPIScriptLauncher environmentForScript:fullPath checkForMain:YES];
    if (venv) {
        if (!explicitUserAction && ![iTermAPIHelper isEnabled]) {
            DLog(@"Not launching %@ because the API is not enabled", fullPath);
            return;
        }
        NSString *name = fullPath.lastPathComponent;
        NSString *mainPyPath = [[[fullPath stringByAppendingPathComponent:name] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"py"];
        [iTermAPIScriptLauncher launchScript:mainPyPath
                                    fullPath:fullPath
                              withVirtualEnv:venv
                                setupCfgPath:[fullPath stringByAppendingPathComponent:@"setup.cfg"]
                          explicitUserAction:explicitUserAction];
        return;
    }

    if ([[fullPath pathExtension] isEqualToString:@"py"]) {
        if (!explicitUserAction && ![iTermAPIHelper isEnabled]) {
            DLog(@"Not launching %@ because the API is not enabled", fullPath);
            return;
        }
        [iTermAPIScriptLauncher launchScript:fullPath
                          explicitUserAction:explicitUserAction];
        return;
    }
    if ([[fullPath pathExtension] isEqualToString:@"scpt"]) {
        NSAppleScript *script;
        NSDictionary *errorInfo = nil;
        NSURL *aURL = [NSURL fileURLWithPath:fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        script = [[NSAppleScript alloc] initWithContentsOfURL:aURL error:&errorInfo];
        if (script) {
            [script executeAndReturnError:&errorInfo];
            if (errorInfo) {
                [self showAlertForScript:fullPath error:errorInfo];
            }
        } else {
            [self showAlertForScript:fullPath error:errorInfo];
        }
        return;
    }
    if ([[NSFileManager defaultManager] itemIsDirectory:fullPath]) {
        iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The script “%@” is malformed.", fullPath.lastPathComponent]
                                                                     actions:@[ @"OK", @"Reveal" ]
                                                                   accessory:nil
                                                                  identifier:@"NoSyncScriptMalformed"
                                                                 silenceable:kiTermWarningTypeTemporarilySilenceable
                                                                     heading:@"Cannot Run Script"
                                                                      window:nil];
        if (selection == kiTermWarningSelection1) {
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:fullPath] ]];
            return;
        }
        return;
    }
    [[NSWorkspace sharedWorkspace] launchApplication:fullPath];
}

// NOTE: This logic needs to be kept in sync with -launchScriptWithAbsolutePath
- (BOOL)couldLaunchScriptWithAbsolutePath:(NSString *)fullPath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
        return NO;
    }
    NSString *venv = [iTermAPIScriptLauncher environmentForScript:fullPath checkForMain:YES];
    if (venv) {
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
    iTermScriptTemplatePickerWindowController *picker = [[iTermScriptTemplatePickerWindowController alloc] initWithWindowNibName:@"iTermScriptTemplatePickerWindowController"];
    [NSApp runModalForWindow:picker.window];
    [picker.window close];

    if (picker.selectedEnvironment == iTermScriptEnvironmentNone ||
        picker.selectedTemplate == iTermScriptTemplateNone) {
        return;
    }

    NSArray<NSString *> *dependencies = nil;
    NSString *pythonVersion = nil;
    NSURL *url = [self runSavePanelForNewScriptWithPicker:picker dependencies:&dependencies pythonVersion:&pythonVersion];
    if (url) {
        [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                            pythonVersion:pythonVersion
                                                                                minimumEnvironmentVersion:0
                                                                                       requiredToContinue:YES
                                                                                           withCompletion:
         ^(iTermPythonRuntimeDownloaderStatus status) {
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
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        NSURL *folder = [NSURL fileURLWithPath:[self folderForFullEnvironmentSavePanelURL:url]];
        NSURL *existingEnv = [folder URLByAppendingPathComponent:@"iterm2env"];
        [[NSFileManager defaultManager] removeItemAtURL:existingEnv error:nil];
        iTermBuildingScriptWindowController *pleaseWait = [iTermBuildingScriptWindowController newPleaseWaitWindowController];
        id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification
                                                                     object:nil
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification * _Nonnull note) {
                                                                     [pleaseWait.window makeKeyAndOrderFront:nil];
                                                                 }];
        _disablePathWatcher++;
        [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:folder
                                                                 eventualLocation:folder
                                                                    pythonVersion:pythonVersion
                                                               environmentVersion:[[iTermPythonRuntimeDownloader sharedInstance] installedVersionWithPythonVersion:pythonVersion]
                                                                     dependencies:dependencies
                                                                   createSetupCfg:YES
                                                                       completion:
         ^(iTermInstallPythonStatus status) {
             [[NSNotificationCenter defaultCenter] removeObserver:token];
             [pleaseWait.window close];
             if (status != iTermInstallPythonStatusOK) {
                 NSAlert *alert = [[NSAlert alloc] init];
                 alert.messageText = @"Installation Failed";
                 alert.informativeText = @"Remove ~/Library/Application Support/iTerm2/iterm2env and try again.";
                 [alert runModal];
                 return;
             }
             [self finishInstallingNewPythonScriptForPicker:picker url:url];
             self->_disablePathWatcher--;
             [self build];
         }];
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
    NSString *app;
    NSString *type;
    BOOL ok = [[NSWorkspace sharedWorkspace] getInfoForFile:destinationTemplatePath application:&app type:&type];
    if (ok) {
        iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Open new script in %@?", app]
                                                                     actions:@[ @"OK", @"Show in Finder" ]
                                                                  identifier:@"NoSyncOpenNewPythonScriptInDefaultEditor"
                                                                 silenceable:kiTermWarningTypePermanentlySilenceable
                                                                      window:nil];
        if (selection == kiTermWarningSelection0) {
            [[NSWorkspace sharedWorkspace] openFile:destinationTemplatePath];
            return;
        }
    }
    [[NSWorkspace sharedWorkspace] selectFile:destinationTemplatePath inFileViewerRootedAtPath:@""];
}

- (NSPopUpButton *)newPythonVersionPopup {
    NSPopUpButton *popUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, 0, 50, 50)];

    NSArray<NSString *> *components = @[ @"iterm2env", @"versions" ];
    NSString *path = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutSpaces];
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
    tokenField.placeholderString = @"Package names";
    tokenField.font = [NSFont systemFontOfSize:13];
    return tokenField;
}

- (NSView *)newAccessoryViewForSavePanelWithTokenField:(NSTokenField *)tokenField
                                    pythonVersionPopup:(NSPopUpButton *)pythonVersionPopup {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 60, 22)];
    [label setEditable:NO];
    [label setStringValue:@"PyPI Dependencies:"];
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
        savePanel.allowedFileTypes = @[ @"" ];
        tokenField = [self newTokenFieldForDependencies];
        pythonVersionPopup = [self newPythonVersionPopup];
        savePanel.accessoryView = [self newAccessoryViewForSavePanelWithTokenField:tokenField
                                                                pythonVersionPopup:pythonVersionPopup];
    } else {
        savePanel.allowedFileTypes = @[ @"py" ];
    }
    savePanel.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];

    if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
        NSURL *url = savePanel.URL;
        NSString *filename = [url lastPathComponent];
        NSString *safeFilename = [filename stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        if ([filename isEqualToString:safeFilename]) {
            *dependencies = tokenField.objectValue;
            *pythonVersionOut = pythonVersionPopup.selectedItem.title;
            return url;
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Spaces Not Allowed";
            alert.informativeText = @"Scripts can't have space characters in their filenames.";
            [alert addButtonWithTitle:@"Use _ Instead of Space"];
            [alert addButtonWithTitle:@"Change Name"];
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
    NSString *python = [self pythonForPicker:picker url:url];
    python = [python stringByDeletingLastPathComponent];
    NSDictionary *subs = @{ @"$$PYTHON_BIN$$": python };
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

- (NSString *)pythonForPicker:(iTermScriptTemplatePickerWindowController *)picker
                          url:(NSURL *)url {
    NSString *fullPath;
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        fullPath = [iTermAPIScriptLauncher prospectivePythonPathForPyenvScriptNamed:url.lastPathComponent];
    } else {
        fullPath = [[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPythonWithPythonVersion:nil];
    }
    return fullPath;
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

- (void)showAlertForScript:(NSString *)fullPath error:(NSDictionary *)errorInfo {
    NSValue *range = errorInfo[NSAppleScriptErrorRange];
    NSString *location = @"Location of error not known.";
    if (range) {
        location = [NSString stringWithFormat:@"The error starts at byte %d of the script.",
                    (int)[range rangeValue].location];
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Problem running script";
    alert.informativeText = [NSString stringWithFormat:@"The script at \"%@\" failed.\n\nThe error was: \"%@\"\n\n%@",
                             fullPath, errorInfo[NSAppleScriptErrorMessage], location];
    [alert runModal];
}

- (NSString *)autolaunchScriptPath {
    return [[NSFileManager defaultManager] autolaunchScriptPath];
}

- (NSString *)legacyAutolaunchScriptPath {
    return [[NSFileManager defaultManager] legacyAutolaunchScriptPath];
}

- (BOOL)shouldRunAutoLaunchScripts {
    if (_ranAutoLaunchScript) {
        return NO;
    }
    return ([[NSFileManager defaultManager] fileExistsAtPath:self.legacyAutolaunchScriptPath] ||
            [[NSFileManager defaultManager] fileExistsAtPath:self.autolaunchScriptPath]);
}

- (void)runAutoLaunchScripts {
    _ranAutoLaunchScript = YES;

    [self runLegacyAutoLaunchScripts];
    [self runModernAutoLaunchScripts];
}

- (void)runModernAutoLaunchScripts {
    NSString *scriptsPath = [[NSFileManager defaultManager] autolaunchScriptPath];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:scriptsPath];
    for (NSString *file in enumerator) {
        if ([file caseInsensitiveCompare:@".DS_Store"] == NSOrderedSame) {
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
    [self launchScriptWithAbsolutePath:path explicitUserAction:NO];
}

- (void)runLegacyAutoLaunchScripts {
    NSDictionary *errorInfo = [NSDictionary dictionary];
    NSURL *aURL = [NSURL fileURLWithPath:self.legacyAutolaunchScriptPath];

    // Make sure our script suite registry is loaded
    [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

    NSAppleScript *autoLaunchScript = [[NSAppleScript alloc] initWithContentsOfURL:aURL
                                                                             error:&errorInfo];
    [autoLaunchScript executeAndReturnError:&errorInfo];
}

#pragma mark - SCEventListenerProtocol

- (void)pathWatcher:(SCEvents *)pathWatcher eventOccurred:(SCEvent *)event {
    if (_disablePathWatcher) {
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
    return [self urlIsUnderScripts:url];
}

@end

NS_ASSUME_NONNULL_END
