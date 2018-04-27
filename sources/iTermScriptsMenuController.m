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
#import "iTermScriptTemplatePickerWindowController.h"
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
    }
    return self;
}

- (void)build {
    NSInteger i = 0;
    while (![_scriptsMenu.itemArray[i].identifier isEqualToString:@"Separator"]) {
        i++;
    }
    i++;
    while (_scriptsMenu.itemArray.count > i) {
        [_scriptsMenu removeItemAtIndex:i];
    }

    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];
    NSDirectoryEnumerator *directoryEnumerator =
        [[NSFileManager defaultManager] enumeratorAtPath:scriptsPath];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *file in directoryEnumerator) {
        if ([[[file pathComponents] firstObject] isEqualToString:@"AutoLaunch"] ||
            [[[file pathComponents] firstObject] isEqualToString:@"AutoLaunch.scpt"]) {
            continue;
        }
        NSString *path = [scriptsPath stringByAppendingPathComponent:file];
        if ([workspace isFilePackageAtPath:path]) {
            [directoryEnumerator skipDescendents];
        }
        BOOL isDirectory;
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];

        if ([iTermAPIScriptLauncher environmentForScript:path]) {
            [files addObject:file];
            [directoryEnumerator skipDescendents];
            continue;
        }

        if ([[file pathExtension] isEqualToString:@"scpt"] ||
            [[file pathExtension] isEqualToString:@"app"] ) {
            [files addObject:file];
        }

        if ([[file pathExtension] isEqualToString:@"py"]) {
            [files addObject:file];
        }
    }
    [files sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *file in files) {
        [self addFile:file toScriptMenu:_scriptsMenu];
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

#pragma mark - Actions

- (void)launchScript:(id)sender {
    NSString *fullPath = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:[sender title]];

    NSString *venv = [iTermAPIScriptLauncher environmentForScript:fullPath];
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
            [self createFullEnvironmentForScriptURL:url];
        }

        NSString *destinationTemplatePath = [self destinationTemplatePathForPicker:picker url:url];
        NSString *template = [self templateForPicker:picker url:url];
        [template writeToURL:[NSURL fileURLWithPath:destinationTemplatePath]
                  atomically:NO
                    encoding:NSUTF8StringEncoding
                       error:nil];
        [[NSWorkspace sharedWorkspace] openFile:destinationTemplatePath];
    }
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
        return savePanel.URL;
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

- (void)createFullEnvironmentForScriptURL:(NSURL *)url {
    NSString *folder = [self folderForFullEnvironmentSavePanelURL:url];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] copyItemAtPath:[iTermAPIScriptLauncher pathToStandardPyenv]
                                            toPath:[folder stringByAppendingPathComponent:@"iterm2env"]
                                             error:nil];
}

- (NSString *)folderForFullEnvironmentSavePanelURL:(NSURL *)url {
    NSString *name = url.path.lastPathComponent;
    NSString *folder = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:name];
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
        fullPath = [iTermAPIScriptLauncher pathToStandardPyenvPython];
    }
    return [fullPath stringByDeletingLastPathComponent];
}

#pragma mark - Private

- (void)addFile:(NSString *)file toScriptMenu:(NSMenu *)scriptMenu {
    NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:file
                                                        action:@selector(launchScript:)
                                                 keyEquivalent:@""];

    [scriptItem setTarget:self];
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

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    NSString *folder = [url.path stringByDeletingLastPathComponent];
    return [folder isEqual:[[NSFileManager defaultManager] scriptsPath]];
}

- (void)panel:(NSSavePanel *)sender didChangeToDirectoryURL:(nullable NSURL *)url {
    sender.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];
}

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
    NSString *path = [url path];
    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];
    return [[path stringByDeletingLastPathComponent] isEqualToString:scriptsPath];
}

@end

NS_ASSUME_NONNULL_END
