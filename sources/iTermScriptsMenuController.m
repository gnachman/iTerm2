//
//  iTermScriptsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/18.
//

#import "iTermScriptsMenuController.h"

#import "DebugLogging.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBuildingScriptWindowController.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptTemplatePickerWindowController.h"
#import "iTermWarning.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "SCEvents.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermScriptsMenuController()<NSOpenSavePanelDelegate, SCEventListenerProtocol>
@end

@implementation iTermScriptsMenuController {
    NSMenu *_scriptsMenu;
    BOOL _ranAutoLaunchScript;
    SCEvents *_events;
}

- (instancetype)initWithMenu:(NSMenu *)menu {
    self = [super init];
    if (self) {
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

- (void)didInstallPythonRuntime:(NSNotification *)notification {
    [self removeInstallMenuItem];
}

- (NSInteger)separatorIndex {
    return [_scriptsMenu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj.identifier isEqualToString:@"Separator"];
    }];
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

    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];

    [self addMenuItemsAt:scriptsPath toMenu:_scriptsMenu];
}

- (void)addMenuItemsAt:(NSString *)root toMenu:(NSMenu *)menu {
    NSDirectoryEnumerator *directoryEnumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:root];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMenu *> *submenus = [NSMutableDictionary dictionary];
    NSSet<NSString *> *scriptExtensions = [NSSet setWithArray:@[ @"scpt", @"app", @"py" ]];
    for (NSString *file in directoryEnumerator) {
        NSString *path = [root stringByAppendingPathComponent:file];
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
        if (isDirectory) {
            [directoryEnumerator skipDescendents];
            if ([workspace isFilePackageAtPath:path] ||
                [iTermAPIScriptLauncher environmentForScript:path checkForMain:NO]) {
                [files addObject:file];
            } else {
                NSMenu *submenu = [[NSMenu alloc] initWithTitle:file];
                submenus[file] = submenu;
                [self addMenuItemsAt:path toMenu:submenu];
                if (submenu.itemArray.count == 0) {
                    [submenus removeObjectForKey:file];
                }
            }
        } else if ([scriptExtensions containsObject:[file pathExtension]]) {
            [files addObject:file];
        }
    }
    [files sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSArray<NSString *> *folders = [submenus.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    for (NSString *folder in folders) {
        NSMenuItem *submenuItem = [[NSMenuItem alloc] init];
        submenuItem.title = folder;
        submenuItem.submenu = submenus[folder];
        [menu addItem:submenuItem];
    }
    for (NSString *file in files) {
        [self addFile:file withFullPath:[root stringByAppendingPathComponent:file] toScriptMenu:menu];
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
        [self removeInstallMenuItem];
    }
}

- (void)removeInstallMenuItem {
    if (_installRuntimeMenuItem) {
        [_scriptsMenu removeItem:_installRuntimeMenuItem];
        _installRuntimeMenuItem = nil;
    }
}

#pragma mark - Actions

- (void)launchScript:(NSMenuItem *)sender {
    NSString *fullPath = sender.identifier;

    NSString *venv = [iTermAPIScriptLauncher environmentForScript:fullPath checkForMain:YES];
    if (venv) {
        [iTermAPIScriptLauncher launchScript:[fullPath stringByAppendingPathComponent:@"main.py"]
                              withVirtualEnv:venv];
        return;
    }

    if ([[[sender title] pathExtension] isEqualToString:@"py"]) {
        [iTermAPIScriptLauncher launchScript:fullPath];
        return;
    }
    if ([[[sender title] pathExtension] isEqualToString:@"scpt"]) {
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
    } else {
        [[NSWorkspace sharedWorkspace] launchApplication:fullPath];
    }
}

- (NSString *)pathToTemplateForPicker:(iTermScriptTemplatePickerWindowController *)picker {
    NSArray<NSString *> *environmentNamePart = @[ @"na", @"basic", @"pyenv" ];
    NSArray<NSString *> *templateNamePart = @[ @"na", @"simple", @"daemon" ];
    NSString *templateName = [NSString stringWithFormat:@"template_%@_%@",
                              environmentNamePart[picker.selectedEnvironment],
                              templateNamePart[picker.selectedTemplate]];
    NSString *templatePath = [[NSBundle mainBundle] pathForResource:templateName ofType:@"py"];
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

    NSURL *url = [self runSavePanelForNewScriptWithPicker:picker];
    if (url) {
        if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
            NSURL *folder = [NSURL fileURLWithPath:[self folderForFullEnvironmentSavePanelURL:url]];
            NSURL *existingEnv = [folder URLByAppendingPathComponent:@"iterm2env"];
            [[NSFileManager defaultManager] removeItemAtURL:existingEnv error:nil];
            iTermBuildingScriptWindowController *pleaseWait = [[iTermBuildingScriptWindowController alloc] initWithWindowNibName:@"iTermBuildingScriptWindowController"];
            pleaseWait.window.alphaValue = 0;
            NSScreen *screen = pleaseWait.window.screen;
            NSRect screenFrame = screen.frame;
            NSSize windowSize = pleaseWait.window.frame.size;
            NSPoint screenCenter = NSMakePoint(NSMinX(screenFrame) + NSWidth(screenFrame) / 2,
                                               NSMinY(screenFrame) + NSHeight(screenFrame) / 2);
            NSPoint windowOrigin = NSMakePoint(screenCenter.x - windowSize.width / 2,
                                               screenCenter.y - windowSize.height / 2);
            [pleaseWait.window setFrameOrigin:windowOrigin];
            pleaseWait.window.alphaValue = 1;

            [pleaseWait.window makeKeyAndOrderFront:nil];
            [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:folder completion:^(BOOL ok) {
                if (ok) {
                    [pleaseWait.window close];
                    [self finishInstallingNewPythonScriptForPicker:picker url:url];
                } else {
                    [pleaseWait.window close];
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Installation Failed";
                    alert.informativeText = @"Remove ~/Library/Application Support/iTerm2/iterm2env and try again.";
                    [alert runModal];
                    return;
                }
            }];
        } else {
            [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithCompletion:^{
                [self finishInstallingNewPythonScriptForPicker:picker url:url];
            }];
        }
    }
}

- (void)finishInstallingNewPythonScriptForPicker:(iTermScriptTemplatePickerWindowController *)picker
                                             url:(NSURL *)url {
    NSString *destinationTemplatePath = [self destinationTemplatePathForPicker:picker url:url];
    NSString *template = [self templateForPicker:picker url:url];
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
                                                                 silenceable:kiTermWarningTypePermanentlySilenceable];
        if (selection == kiTermWarningSelection0) {
            [[NSWorkspace sharedWorkspace] openFile:destinationTemplatePath];
            return;
        }
    }
    [[NSWorkspace sharedWorkspace] selectFile:destinationTemplatePath inFileViewerRootedAtPath:@""];
}

- (NSURL *)runSavePanelForNewScriptWithPicker:(iTermScriptTemplatePickerWindowController *)picker {
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.delegate = self;
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        savePanel.allowedFileTypes = @[ @"" ];
    } else {
        savePanel.allowedFileTypes = @[ @"py" ];
    }
    savePanel.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];
    if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
        NSURL *url = savePanel.URL;
        NSString *filename = [url lastPathComponent];
        NSString *safeFilename = [filename stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        if ([filename isEqualToString:safeFilename]) {
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
                return [self runSavePanelForNewScriptWithPicker:picker];
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

- (NSString *)folderForFullEnvironmentSavePanelURL:(NSURL *)url {
    NSString *name = url.path.lastPathComponent;
    NSString *folder = [[[NSFileManager defaultManager] scriptsPathWithoutSpaces] stringByAppendingPathComponent:name];
    return folder;
}

- (NSString *)destinationTemplatePathForPicker:(iTermScriptTemplatePickerWindowController *)picker
                                           url:(NSURL *)url {
    if (picker.selectedEnvironment == iTermScriptEnvironmentPrivateEnvironment) {
        NSString *folder = [self folderForFullEnvironmentSavePanelURL:url];
        return [folder stringByAppendingPathComponent:@"main.py"];
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
        fullPath = [[iTermPythonRuntimeDownloader sharedInstance] pathToStandardPyenvPython];
    }
    return fullPath;
}

#pragma mark - Private

- (void)addFile:(NSString *)file withFullPath:(NSString *)path toScriptMenu:(NSMenu *)scriptMenu {
    NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:file
                                                        action:@selector(launchScript:)
                                                 keyEquivalent:@""];

    [scriptItem setTarget:self];
    scriptItem.identifier = path;
    [scriptMenu addItem:scriptItem];
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
    for (NSString *file in [[NSFileManager defaultManager] enumeratorAtPath:scriptsPath]) {
        NSString *path = [scriptsPath stringByAppendingPathComponent:file];
        [self runAutoLaunchScript:path];
    }
}

- (void)runAutoLaunchScript:(NSString *)path {
    [iTermAPIScriptLauncher launchScript:path];
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
