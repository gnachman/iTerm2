/*
 **  Copyright (c) 2011
 **
 **  Author: Jack Chen (chendo)
 **
 **  Project: iTerm
 **
 **  Description: Terminal Router
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermSemanticHistoryController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCachingFileManager.h"
#import "iTermLaunchServices.h"
#import "iTermPathCleaner.h"
#import "iTermPathFinder.h"
#import "iTermSemanticHistoryPrefsController.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "RegexKitLite.h"
#include <sys/utsname.h>

NSString *const kSemanticHistoryPathSubstitutionKey = @"semanticHistory.path";
NSString *const kSemanticHistoryPrefixSubstitutionKey = @"semanticHistory.prefix";
NSString *const kSemanticHistorySuffixSubstitutionKey = @"semanticHistory.suffix";
NSString *const kSemanticHistoryWorkingDirectorySubstitutionKey = @"semanticHistory.workingDirectory";
NSString *const kSemanticHistoryLineNumberKey = @"semanticHistory.lineNumber";
NSString *const kSemanticHistoryColumnNumberKey = @"semanticHistory.columnNumber";

@implementation iTermSemanticHistoryController

@synthesize prefs = prefs_;
@synthesize delegate = delegate_;

- (void)dealloc {
    [prefs_ release];
    [super dealloc];
}

- (NSString *)cleanedUpPathFromPath:(NSString *)path
                             suffix:(NSString *)suffix
                   workingDirectory:(NSString *)workingDirectory
                extractedLineNumber:(NSString **)lineNumber
                       columnNumber:(NSString **)columnNumber {
    iTermPathCleaner *cleaner = [[iTermPathCleaner alloc] initWithPath:path
                                                                suffix:suffix
                                                      workingDirectory:workingDirectory];
    cleaner.fileManager = self.fileManager;
    [cleaner cleanSynchronously];
    if (lineNumber) {
        *lineNumber = cleaner.lineNumber;
    }
    if (columnNumber) {
        *columnNumber = cleaner.columnNumber;
    }
    return cleaner.cleanPath;
}

- (NSString *)preferredEditorIdentifier {
    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryBestEditorAction]) {
        return [iTermSemanticHistoryPrefsController bestEditor];
    } else if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryEditorAction]) {
        return [iTermSemanticHistoryPrefsController schemeForEditor:prefs_[kSemanticHistoryEditorKey]] ?
            prefs_[kSemanticHistoryEditorKey] : nil;
    } else {
        return nil;
    }
}

- (void)launchAtomWithPath:(NSString *)path {
    [self launchAppWithBundleIdentifier:kAtomIdentifier path:path];
}

- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier path:(NSString *)path {
    if (!path) {
        return;
    }
    [self launchAppWithBundleIdentifier:bundleIdentifier args:@[ path ]];
}

- (NSBundle *)applicationBundleWithIdentifier:(NSString *)bundleIdentifier {
    NSString *bundlePath =
        [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleIdentifier];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    return bundle;
}

- (NSString *)executableInApplicationBundle:(NSBundle *)bundle {
    NSString *executable = [bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    executable = [executable stringByAppendingPathComponent:
                            [bundle objectForInfoDictionaryKey:(id)kCFBundleExecutableKey]];
    return executable;
}

- (NSString *)emacsClientInApplicationBundle:(NSBundle *)bundle {
    DLog(@"Trying to find emacsclient in %@", bundle.bundlePath);
    struct utsname uts;
    int status = uname(&uts);
    if (status) {
        DLog(@"Failed to get uname: %s", strerror(errno));
        return nil;
    }
    NSString *arch = [NSString stringWithUTF8String:uts.machine];
    
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSMutableArray<NSString *> *bindirs = [NSMutableArray array];
    NSURL *folder = [NSURL fileURLWithPath:[bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"]];
    for (NSURL *url in [[iTermCachingFileManager cachingFileManager] enumeratorAtURL:folder
                                                          includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                        errorHandler:nil]) {
        NSString *file = url.path.lastPathComponent;
        DLog(@"Consider: %@", file);
        if (![file hasPrefix:@"bin-"]) {
            DLog(@"Reject: does not start with bin-");
            continue;
        }
        BOOL isdir = NO;
        [[iTermCachingFileManager cachingFileManager] fileExistsAtPath:url.path isDirectory:&isdir];
        if (!isdir) {
            DLog(@"Reject: not a folder");
            continue;
        }
        [bindirs addObject:file];
    }
    
    // bin-i386-10_5
    NSString *regex = @"^bin-([^-]+)-([0-9]+)_([0-9]+)$";
    NSArray<NSString *> *contenders = [bindirs filteredArrayUsingBlock:^BOOL(NSString *dir) {
        NSArray<NSString *> *captures = [[dir arrayOfCaptureComponentsMatchedByRegex:regex] firstObject];
        DLog(@"Captures for %@ are %@", dir, captures);
        if (captures.count != 4) {
            return NO;
        }
        if (![captures[1] isEqualToString:arch]) {
            return NO;
        }
        if ([captures[2] integerValue] != version.majorVersion) {
            return NO;
        }
        if ([captures[3] integerValue] > version.minorVersion) {
            return NO;
        }
        DLog(@"It's a keeper");
        return YES;
    }];
    
    NSString *best = [contenders maxWithBlock:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        NSArray<NSString *> *cap1 = [obj1 arrayOfCaptureComponentsMatchedByRegex:regex].firstObject;
        NSArray<NSString *> *cap2 = [obj2 arrayOfCaptureComponentsMatchedByRegex:regex].firstObject;
        
        NSInteger minor1 = [cap1[3] integerValue];
        NSInteger minor2 = [cap2[3] integerValue];
        return [@(minor1) compare:@(minor2)];
    }];
    DLog(@"Best is %@", best);
    if (!best) {
        return nil;
    }
    NSString *executable = [bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    executable = [executable stringByAppendingPathComponent:best];
    executable = [executable stringByAppendingPathComponent:@"emacsclient"];
    DLog(@"I guess emacsclient is %@", executable);
    return executable;
}

- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier args:(NSArray *)args {
    NSBundle *bundle = [self applicationBundleWithIdentifier:bundleIdentifier];
    if (!bundle) {
        DLog(@"No bundle for %@", bundleIdentifier);
        return;
    }
    NSString *executable = [self executableInApplicationBundle:bundle];
    if (!executable) {
        DLog(@"No executable for %@ in %@", bundleIdentifier, bundle);
        return;
    }
    DLog(@"Launch %@: %@ %@", bundleIdentifier, executable, args);
    [self launchTaskWithPath:executable arguments:args wait:NO];
}

- (void)launchVSCodeWithPath:(NSString *)path {
    assert(path);
    if (!path) {
        // I don't expect this to ever happen.
        return;
    }
    NSString *bundlePath = [self absolutePathForAppBundleWithIdentifier:kVSCodeIdentifier];
    if (bundlePath) {
        NSString *codeExecutable =
        [bundlePath stringByAppendingPathComponent:@"Contents/Resources/app/bin/code"];
        if ([self.fileManager fileExistsAtPath:codeExecutable]) {
            DLog(@"Launch VSCode %@ %@", codeExecutable, path);
            [self launchTaskWithPath:codeExecutable arguments:@[ path, @"-g" ] wait:NO];
        } else {
            // This isn't as good as opening "code -g" because it always opens a new instance
            // of the app but it's the OS-sanctioned way of running VSCode.  We can't
            // use AppleScript because it won't open the file to a particular line number.
            [self launchAppWithBundleIdentifier:kVSCodeIdentifier path:path];
        }
    }
}

- (void)launchEmacsWithArguments:(NSArray *)args {
    // Try to find emacsclient.
    NSBundle *bundle = [self applicationBundleWithIdentifier:kEmacsAppIdentifier];
    if (!bundle) {
        DLog(@"Failed to find emacs bundle");
        return;
    }
    NSString *emacsClient = [self emacsClientInApplicationBundle:bundle];
    if (!emacsClient) {
        DLog(@"No emacsClient in %@", bundle);
        DLog(@"Launching emacs the old-fashioned way");
        [self launchAppWithBundleIdentifier:kEmacsAppIdentifier
                                       args:[@[ @"emacs" ] arrayByAddingObjectsFromArray:args]];
        return;
    }

    // Find the regular emacs exectuable to fall back to
    NSString *emacs = [self executableInApplicationBundle:bundle];
    if (!emacs) {
        DLog(@"No executable for emacs in %@", bundle);
        return;
    }
    NSArray<NSString *> *fallbackParts = @[ emacs ];
    NSString *fallback = [[fallbackParts mapWithBlock:^id(NSString *anObject) {
        return [anObject stringWithEscapedShellCharactersIncludingNewlines:YES];
    }] componentsJoinedByString:@" "];
    
    // Run emacsclient -a "emacs <args>" <args>
    // That'll use emacsclient if possible and fall back to real emacs if it fails.
    // Normally it will fail unless you've enabled the daemon.
    [self launchTaskWithPath:emacsClient
                   arguments:[@[ @"-n", @"-a", fallback, args] flattenedArray]
                        wait:NO];

}

- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)bundleId {
    return [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleId];
}

- (void)launchSublimeTextWithBundleIdentifier:(NSString *)bundleId path:(NSString *)path {
    assert(path);
    if (!path) {
        // I don't expect this to ever happen.
        return;
    }
    NSString *bundlePath = [self absolutePathForAppBundleWithIdentifier:bundleId];
    if (bundlePath) {
        NSString *sublExecutable =
            [bundlePath stringByAppendingPathComponent:@"Contents/SharedSupport/bin/subl"];
        if ([self.fileManager fileExistsAtPath:sublExecutable]) {
            DLog(@"Launch sublime text %@ %@", sublExecutable, path);
            [self launchTaskWithPath:sublExecutable arguments:@[ path ] wait:NO];
        } else {
            // This isn't as good as opening "subl" because it always opens a new instance
            // of the app but it's the OS-sanctioned way of running Sublimetext.  We can't
            // use AppleScript because it won't open the file to a particular line number.
            [self launchAppWithBundleIdentifier:bundleId path:path];
        }
    }
}

+ (NSArray *)bundleIdsThatSupportOpeningToLineNumber {
    return @[ kAtomIdentifier,
              kVSCodeIdentifier,
              kSublimeText2Identifier,
              kSublimeText3Identifier,
              kMacVimIdentifier,
              kTextmateIdentifier,
              kTextmate2Identifier,
              kBBEditIdentifier,
              kEmacsAppIdentifier];
}

- (void)openFile:(NSString *)path
    inEditorWithBundleId:(NSString *)identifier
          lineNumber:(NSString *)lineNumber
        columnNumber:(NSString *)columnNumber {
    if (identifier) {
        DLog(@"openFileInEditor. editor=%@", [self preferredEditorIdentifier]);
        if ([identifier isEqualToString:kAtomIdentifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            if (columnNumber != nil) {
                path = [path stringByAppendingFormat:@":%@", columnNumber];
            }
            [self launchAtomWithPath:path];
        } else if ([identifier isEqualToString:kVSCodeIdentifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            if (columnNumber != nil) {
                path = [path stringByAppendingFormat:@":%@", columnNumber];
            }
            [self launchVSCodeWithPath:path];
        } else if ([identifier isEqualToString:kSublimeText2Identifier] ||
                   [identifier isEqualToString:kSublimeText3Identifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            if (columnNumber != nil) {
                path = [path stringByAppendingFormat:@":%@", columnNumber];
            }
            NSString *bundleId;
            if ([identifier isEqualToString:kSublimeText3Identifier]) {
                bundleId = kSublimeText3Identifier;
            } else {
                bundleId = kSublimeText2Identifier;
            }

            [self launchSublimeTextWithBundleIdentifier:bundleId path:path];
        } else if ([identifier isEqualToString:kEmacsAppIdentifier]) {
            NSMutableArray *args = [NSMutableArray array];
            if (path) {
                [args addObject:path];
                if (lineNumber) {
                    if (columnNumber) {
                        [args insertObject:[NSString stringWithFormat:@"+%@:%@", lineNumber, columnNumber] atIndex:0];
                    } else {
                        [args insertObject:[NSString stringWithFormat:@"+%@", lineNumber] atIndex:0];
                    }
                }
            }
            [self launchEmacsWithArguments:args];
        } else {
            path = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
            NSURL *url = nil;
            NSString *editorIdentifier = identifier;
            if (lineNumber) {
                url = [NSURL URLWithString:[NSString stringWithFormat:
                                            @"%@://open?url=file://%@&line=%@",
                                            [iTermSemanticHistoryPrefsController schemeForEditor:editorIdentifier],
                                            path, lineNumber]];
            } else {
                url = [NSURL URLWithString:[NSString stringWithFormat:
                                            @"%@://open?url=file://%@",
                                            [iTermSemanticHistoryPrefsController schemeForEditor:editorIdentifier],
                                            path]];
            }
            DLog(@"Open url %@", url);
            // BBEdit and TextMate share a URL scheme, so this disambiguates.
            [self openURL:url editorIdentifier:editorIdentifier];
        }
    }
}

- (void)openFileInEditor:(NSString *)path lineNumber:(NSString *)lineNumber columnNumber:(NSString *)columnNumber {
    [self openFile:path inEditorWithBundleId:[self preferredEditorIdentifier] lineNumber:lineNumber columnNumber:columnNumber];
}

- (BOOL)activatesOnAnyString {
    return [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
}

- (void)launchTaskWithPath:(NSString *)path arguments:(NSArray *)arguments wait:(BOOL)wait {
    NSTask *task = [NSTask launchedTaskWithLaunchPath:path arguments:arguments];
    if (wait) {
        [task waitUntilExit];
    }
}

- (BOOL)openFile:(NSString *)fullPath {
    DLog(@"Open file %@", fullPath);
    return [[iTermLaunchServices sharedInstance] openFile:fullPath];
}

- (BOOL)openURL:(NSURL *)url editorIdentifier:(NSString *)editorIdentifier {
    DLog(@"Open URL %@", url);
    if (editorIdentifier) {
        return [[NSWorkspace sharedWorkspace] openURLs:@[ url ]
                               withAppBundleIdentifier:editorIdentifier
                                               options:NSWorkspaceLaunchDefault
                        additionalEventParamDescriptor:nil
                                     launchIdentifiers:NULL];
    } else {
        return [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (BOOL)openURL:(NSURL *)url {
    return [self openURL:url editorIdentifier:nil];
}

- (BOOL)openPath:(NSString *)cleanedUpPath
   orRawFilename:(NSString *)rawFileName
       substitutions:(NSDictionary *)substitutions
      lineNumber:(NSString *)lineNumber
    columnNumber:(NSString *)columnNumber {
    DLog(@"openPath:%@ rawFileName:%@ substitutions:%@ lineNumber:%@ columnNumber:%@",
         cleanedUpPath, rawFileName, substitutions, lineNumber, columnNumber);
    BOOL isDirectory;

    NSString *path;
    BOOL isRawAction = [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
    if (isRawAction) {
        path = rawFileName;
        lineNumber = @"";
        columnNumber = @"";
        DLog(@"Is a raw action. Use path %@", rawFileName);
    } else {
        path = cleanedUpPath;
        DLog(@"Not a raw action. New path is %@, line number is %@", path, lineNumber);
    }

    NSString *script = [prefs_ objectForKey:kSemanticHistoryTextKey];
    NSMutableDictionary *augmentedSubs = [[substitutions mutableCopy] autorelease];
    augmentedSubs[@"1"] = path ? [path stringWithEscapedShellCharactersIncludingNewlines:YES] : @"";
    augmentedSubs[@"2"] = lineNumber ? lineNumber : @"";
    augmentedSubs[@"3"] = substitutions[kSemanticHistoryPrefixSubstitutionKey];
    augmentedSubs[@"4"] = substitutions[kSemanticHistorySuffixSubstitutionKey];
    augmentedSubs[@"5"] = substitutions[kSemanticHistoryWorkingDirectorySubstitutionKey];
    script = [script stringByReplacingVariableReferencesWithVariables:augmentedSubs];

    DLog(@"After escaping backrefs, script is %@", script);

    if (isRawAction) {
        DLog(@"Launch raw action: /bin/sh -c %@", script);
        [self launchTaskWithPath:@"/bin/sh" arguments:@[ @"-c", script ] wait:YES];
        return YES;
    }

    if (![self.fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        DLog(@"No file exists at %@, not running semantic history", path);
        return NO;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryCommandAction]) {
        DLog(@"Running /bin/sh -c %@", script);
        [self launchTaskWithPath:@"/bin/sh" arguments:@[ @"-c", script ] wait:YES];
        return YES;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryCoprocessAction]) {
        DLog(@"Launch coprocess with script %@", script);
        assert(delegate_);
        [delegate_ semanticHistoryLaunchCoprocessWithCommand:script];
        return YES;
    }

    if (isDirectory) {
        DLog(@"Open directory %@", path);
        [self openFile:path];
        return YES;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryUrlAction]) {
        NSString *url = prefs_[kSemanticHistoryTextKey];
        // Replace the path with a non-shell-escaped path.
        augmentedSubs[@"1"] = path ?: @"";
        // Percent-escape all the arguments.
        for (NSString *key in augmentedSubs.allKeys) {
            augmentedSubs[key] =
                [augmentedSubs[key] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
        }
        url = [url stringByReplacingVariableReferencesWithVariables:augmentedSubs];
        DLog(@"Open url %@", url);
        [self openURL:[NSURL URLWithUserSuppliedString:url]];
        return YES;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryEditorAction] &&
        [self preferredEditorIdentifier]) {
        // Action is to open in a specific editor, so open it in the editor.
        [self openFileInEditor:path lineNumber:lineNumber columnNumber:columnNumber];
        return YES;
    }

    if (lineNumber) {
        NSString *appBundleId = [self bundleIdForDefaultAppForFile:path];
        if ([self canOpenFileWithLineNumberUsingEditorWithBundleId:appBundleId]) {
            DLog(@"A line number is present and I know how to open this file to the line number using %@. Do so.",
                 appBundleId);
            [self openFile:path inEditorWithBundleId:appBundleId lineNumber:lineNumber columnNumber:columnNumber];
            return YES;
        }
    }

    [self openFile:path];
    return YES;
}

- (BOOL)canOpenFileWithLineNumberUsingEditorWithBundleId:(NSString *)appBundleId {
    return [[self.class bundleIdsThatSupportOpeningToLineNumber] containsObject:appBundleId];
}

- (NSString *)bundleIdForDefaultAppForFile:(NSString *)file {
    NSURL *fileUrl = [NSURL fileURLWithPath:file];
    return [self bundleIdForDefaultAppForURL:fileUrl];
}

- (NSString *)bundleIdForDefaultAppForURL:(NSURL *)fileUrl {
    NSURL *appUrl = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:fileUrl];
    if (!appUrl) {
        return nil;
    }

    NSBundle *appBundle = [NSBundle bundleWithURL:appUrl];
    if (!appBundle) {
        return nil;
    }
    return [appBundle bundleIdentifier];
}

- (BOOL)defaultAppForFileIsEditor:(NSString *)file {
    return [iTermSemanticHistoryPrefsController bundleIdIsEditor:[self bundleIdForDefaultAppForFile:file]];
}

- (NSString *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                         suffix:(NSString *)afterStringIn
                               workingDirectory:(NSString *)workingDirectory
                           charsTakenFromPrefix:(int *)charsTakenFromPrefixPtr
                           charsTakenFromSuffix:(int *)suffixChars
                                 trimWhitespace:(BOOL)trimWhitespace {
    iTermPathFinder *pathfinder = [[iTermPathFinder alloc] initWithPrefix:beforeStringIn
                                                                   suffix:afterStringIn
                                                         workingDirectory:workingDirectory
                                                           trimWhitespace:trimWhitespace];
    pathfinder.fileManager = self.fileManager;
    [pathfinder searchSynchronously];
    return pathfinder.path;
}

- (iTermPathFinder *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                                suffix:(NSString *)afterStringIn
                                      workingDirectory:(NSString *)workingDirectory
                                        trimWhitespace:(BOOL)trimWhitespace
                                            completion:(void (^)(NSString *path, int prefixChars, int suffixChars))completion {
    iTermPathFinder *pathfinder = [[iTermPathFinder alloc] initWithPrefix:beforeStringIn
                                                                   suffix:afterStringIn
                                                         workingDirectory:workingDirectory
                                                           trimWhitespace:trimWhitespace];
    pathfinder.fileManager = self.fileManager;
    __weak __typeof(pathfinder) weakPathfinder = pathfinder;
    [pathfinder searchWithCompletion:^{
        __strong __typeof(pathfinder) strongPathfinder = weakPathfinder;
        if (!strongPathfinder) {
            return;
        }
        completion(strongPathfinder.path, strongPathfinder.prefixChars, strongPathfinder.suffixChars);
    }];
    return pathfinder;
}

- (NSFileManager *)fileManager {
    return [iTermCachingFileManager cachingFileManager];
}

@end
