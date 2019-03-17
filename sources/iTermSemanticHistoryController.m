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
#import "iTermLaunchServices.h"
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

@implementation iTermSemanticHistoryController

@synthesize prefs = prefs_;
@synthesize delegate = delegate_;

- (void)dealloc {
    [prefs_ release];
    [super dealloc];
}

- (BOOL)fileExistsAtPathLocally:(NSString *)path {
    return [self.fileManager fileExistsAtPathLocally:path
                              additionalNetworkPaths:[[iTermAdvancedSettingsModel pathsToIgnore] componentsSeparatedByString:@","]];
}

- (BOOL)fileHasForbiddenPrefix:(NSString *)path {
    return [self.fileManager fileHasForbiddenPrefix:path
                             additionalNetworkPaths:[[iTermAdvancedSettingsModel pathsToIgnore] componentsSeparatedByString:@","]];
}

- (NSString *)cleanedUpPathFromPath:(NSString *)path
                             suffix:(NSString *)suffix
                   workingDirectory:(NSString *)workingDirectory
                extractedLineNumber:(NSString **)lineNumber
                       columnNumber:(NSString **)columnNumber {
    if (lineNumber) {
        *lineNumber = nil;
    }
    if (columnNumber) {
        *columnNumber = nil;
    }
    NSString *result = [self reallyComputeCleanedUpPathFromPath:path
                                                         suffix:suffix
                                               workingDirectory:workingDirectory
                                            extractedLineNumber:lineNumber
                                                   columnNumber:columnNumber];
    if (!result) {
        // If path doesn't exist and it starts with "a/" or "b/" (from `diff`).
        if ([path isMatchedByRegex:@"^[ab]/"]) {
            DLog(@"  Treating as diff path");
            // strip the prefix off ...
            path = [path stringByReplacingOccurrencesOfRegex:@"^[ab]/"
                                                  withString:@""];

            // ... and calculate the full path again
            result = [self reallyComputeCleanedUpPathFromPath:path
                                                       suffix:suffix
                                             workingDirectory:workingDirectory
                                          extractedLineNumber:lineNumber
                                                 columnNumber:columnNumber];
        }
    }
    return result;
}

- (NSString *)reallyComputeCleanedUpPathFromPath:(NSString *)path
                                          suffix:(NSString *)suffix
                                workingDirectory:(NSString *)workingDirectory
                             extractedLineNumber:(NSString **)lineNumber
                                    columnNumber:(NSString **)columnNumber {
    NSString *stringToSearchForLineAndColumn = suffix;
    NSString *pathWithoutNearbyGunk = [self pathByStrippingEnclosingPunctuationFromPath:path
                                                                     lineAndColumnMatch:&stringToSearchForLineAndColumn];
    if (!pathWithoutNearbyGunk) {
        return nil;
    }
    if (lineNumber != nil || columnNumber != nil) {
        if (stringToSearchForLineAndColumn) {
            [self extractFromSuffix:stringToSearchForLineAndColumn lineNumber:lineNumber columnNumber:columnNumber];
        }
    }
    NSString *fullPath = [self getFullPath:pathWithoutNearbyGunk workingDirectory:workingDirectory];
    return fullPath;
}

- (NSString *)pathByStrippingEnclosingPunctuationFromPath:(NSString *)path
                                       lineAndColumnMatch:(NSString **)lineAndColumnMatch {
    if (!path || [path length] == 0) {
        DLog(@"  no: it is empty");
        return nil;
    }

    // If it's in any form of bracketed delimiters, strip them
    path = [path stringByRemovingEnclosingBrackets];

    // Strip various trailing characters that are unlikely to be part of the file name.
    NSString *trailingPunctuationRegex = @"[.,:]$";
    path = [path stringByReplacingOccurrencesOfRegex:trailingPunctuationRegex
                                          withString:@""];

    // Try to chop off a trailing line/column number.
    NSArray<NSString *> *regexes = [self.lineAndColumnNumberRegexes mapWithBlock:^id(NSString *anObject) {
        return [anObject stringByAppendingString:@"$"];
    }];
    for (NSString *regex in regexes) {
        NSString *match = [path stringByMatching:regex];
        if (!match) {
            continue;
        }
        if (lineAndColumnMatch) {
            *lineAndColumnMatch = match;
        }
        return [path stringByDroppingLastCharacters:match.length];
    }

    // No trailing line/column number. Drop a trailing paren.
    if ([path hasSuffix:@")"]) {
        return [path stringByDroppingLastCharacters:1];
    }

    return path;
}

- (NSArray<NSString *> *)lineAndColumnNumberRegexes {
    return @[ @":(\\d+):(\\d+)",
              @":(\\d+)",
              @"\\[(\\d+), ?(\\d+)]",
              @"\", line (\\d+), column (\\d+)",
              @"\\((\\d+), ?(\\d+)\\)" ];
}

- (void)extractFromSuffix:(NSString *)suffix lineNumber:(NSString **)lineNumber columnNumber:(NSString **)columnNumber {
    NSArray<NSString *> *regexes = [[self lineAndColumnNumberRegexes] mapWithBlock:^id(NSString *anObject) {
        return [@"^" stringByAppendingString:anObject];
    }];
    for (NSString *regex in regexes) {
        NSString *match = [suffix stringByMatching:regex];
        if (!match) {
            continue;
        }
        const NSInteger matchLength = match.length;
        if (matchLength < suffix.length) {
            // If part of `suffix` would remain, we can't use it.
            continue;
        }
        DLog(@"  Suffix of %@ matches regex %@", suffix, regex);
        NSArray<NSArray<NSString *> *> *matches = [suffix arrayOfCaptureComponentsMatchedByRegex:regex];
        NSArray<NSString *> *captures = matches.firstObject;
        if (captures.count > 1 && lineNumber) {
            *lineNumber = captures[1];
        }
        if (captures.count > 2 && columnNumber) {
            *columnNumber = captures[2];
        }
        return;
    }
}

- (NSString *)getFullPath:(NSString *)pathExLineNumberAndColumn
         workingDirectory:(NSString *)workingDirectory {
    DLog(@"Check if %@ is a valid path in %@", pathExLineNumberAndColumn, workingDirectory);
    // TODO(chendo): Move regex, define capture semantics in config file/prefs
    if (!pathExLineNumberAndColumn || [pathExLineNumberAndColumn length] == 0) {
        DLog(@"  no: it is empty");
        return nil;
    }

    NSString *path = [pathExLineNumberAndColumn stringByExpandingTildeInPath];
    DLog(@"  Strip line number suffix leaving %@", path);
    if ([path length] == 0) {
        // Everything was stripped out, meaning we'd try to open the working directory.
        return nil;
    }
    if ([path rangeOfRegex:@"^/"].location == NSNotFound) {
        path = [workingDirectory stringByAppendingPathComponent:path];
        DLog(@"  Prepend working directory, giving %@", path);
    }

    DLog(@"  Checking if file exists locally: %@", path);

    // NOTE: The path used to be standardized first. While that would allow us to catch
    // network paths, it also caused filesystem access that would hit network paths.
    // That was also true for fileURLWithPath:.
    //
    // I think the statfs() flag check ought to be enough to prevent network access, anyway.
    // A second check for forbidden prefixes is performed below to ensure backward compatibility
    // and respect for explicitly excluded paths. The latter category will now
    // be stat()ed, although they were always stat()ed because of unintentional
    // disk access in the old code.

    if ([self fileExistsAtPathLocally:path]) {
        DLog(@"    YES: A file exists at %@", path);
        NSURL *url = [NSURL fileURLWithPath:path];

        // Resolve path by removing ./ and ../ etc
        path = [[url standardizedURL] path];
        DLog(@"    Check standardized path for forbidden prefix %@", path);

        if ([self fileHasForbiddenPrefix:path]) {
            DLog(@"    NO: Standardized path has forbidden prefix.");
            return nil;
        }
        return path;
    }
    DLog(@"     NO: no valid path found");
    return nil;
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
    for (NSURL *url in [NSFileManager.defaultManager enumeratorAtURL:folder
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
        [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isdir];
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

- (NSArray<NSString *> *)splitString:(NSString *)string {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    __block NSRange lastRange = NSMakeRange(0, 0);
    [string enumerateStringsMatchedByRegex:@"([^\t ()]*)([\t ()])"
                                   options:0
                                   inRange:NSMakeRange(0, string.length)
                                     error:nil
                        enumerationOptions:0
                                usingBlock:^(NSInteger captureCount,
                                             NSString *const *capturedStrings,
                                             const NSRange *capturedRanges,
                                             volatile BOOL *const stop) {
                                    [parts addObject:capturedStrings[1]];
                                    [parts addObject:capturedStrings[2]];
                                    lastRange = capturedRanges[2];
                                }];
    const NSInteger suffixStartIndex = NSMaxRange(lastRange);
    if (suffixStartIndex < string.length) {
        [parts addObject:[string substringFromIndex:suffixStartIndex]];
    }
    return parts;
}

- (NSString *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                         suffix:(NSString *)afterStringIn
                               workingDirectory:(NSString *)workingDirectory
                           charsTakenFromPrefix:(int *)charsTakenFromPrefixPtr
                           charsTakenFromSuffix:(int *)suffixChars
                                 trimWhitespace:(BOOL)trimWhitespace {
    BOOL workingDirectoryIsOk = [self fileExistsAtPathLocally:workingDirectory];
    if (!workingDirectoryIsOk) {
        DLog(@"Working directory %@ is a network share or doesn't exist. Not using it for context.",
             workingDirectory);
    }

    DLog(@"Brute force path from prefix <<%@>>, suffix <<%@>> directory=%@",
         beforeStringIn, afterStringIn, workingDirectory);

    // Split "Foo Bar" to ["Foo", " ", "Bar"]
    NSArray *beforeChunks = [self splitString:beforeStringIn];
    NSArray *afterChunks = [self splitString:afterStringIn];

    NSMutableString *left = [NSMutableString string];
    int iterationsBeforeQuitting = 100;  // Bail after 100 iterations if nothing is still found.
    NSMutableSet *paths = [NSMutableSet set];
    NSCharacterSet *whitespaceCharset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (int i = [beforeChunks count]; i >= 0; i--) {
        NSString *beforeChunk = @"";
        if (i < [beforeChunks count]) {
            beforeChunk = beforeChunks[i];
        }

        [left insertString:beforeChunk atIndex:0];
        NSMutableString *right = [NSMutableString string];
        // Do not search more than 10 chunks forward to avoid starving leftward search.
        for (int j = 0; j < MAX(1, afterChunks.count) && j < 10; j++) {
            NSString *rightChunk = @"";
            if (j < afterChunks.count) {
                rightChunk = afterChunks[j];
            }
            [right appendString:rightChunk];

            NSString *possiblePath = [left stringByAppendingString:right];
            NSString *trimmedPath = possiblePath;
            if (trimWhitespace) {
                trimmedPath = [trimmedPath stringByTrimmingCharactersInSet:whitespaceCharset];
            }
            if ([paths containsObject:[NSString stringWithString:trimmedPath]]) {
                continue;
            }
            [paths addObject:[[trimmedPath copy] autorelease]];

            // Replace \x with x for x in: space, (, [, ], \, ).
            NSString *removeEscapingSlashes = @"\\\\([ \\(\\[\\]\\\\)])";
            trimmedPath = [trimmedPath stringByReplacingOccurrencesOfRegex:removeEscapingSlashes withString:@"$1"];

            // Some programs will thoughtlessly print a filename followed by some silly suffix.
            // We'll try versions with and without a questionable suffix. The version
            // with the suffix is always preferred if it exists.
            static NSArray *questionableSuffixes;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                questionableSuffixes = [@[ @"!", @"?", @".", @",", @";", @":", @"...", @"…" ] retain];
            });
            for (NSString *modifiedPossiblePath in [self pathsFromPath:trimmedPath byRemovingBadSuffixes:questionableSuffixes]) {
                BOOL exists = NO;
                if (workingDirectoryIsOk || [modifiedPossiblePath hasPrefix:@"/"]) {
                    exists = ([self cleanedUpPathFromPath:modifiedPossiblePath
                                                   suffix:nil
                                         workingDirectory:workingDirectory
                                      extractedLineNumber:nil
                                             columnNumber:nil] != nil);
                }
                if (exists) {
                    NSString *extra = @"";
                    if (j + 1 < afterChunks.count) {
                        extra = [self columnAndLineNumberFromChunks:[afterChunks subarrayFromIndex:j + 1]];
                    }
                    NSString *extendedPath = [modifiedPossiblePath stringByAppendingString:extra];
                    [right appendString:extra];
                    
                    if (charsTakenFromPrefixPtr) {
                        if (trimWhitespace &&
                            [[right stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length] == 0) {
                            // trimmedPath is trim(left + right). If trim(right) is empty
                            // then we don't want to count trailing whitespace from left in the chars
                            // taken from prefix.
                            *charsTakenFromPrefixPtr = [[left stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length];
                        } else {
                            *charsTakenFromPrefixPtr = left.length;
                        }
                    }
                    if (suffixChars) {
                        NSInteger lengthOfBadSuffix = extra.length ? 0 : trimmedPath.length - modifiedPossiblePath.length;
                        int n;
                        if (trimWhitespace) {
                            n = [[right stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length] - lengthOfBadSuffix;
                        } else {
                            n = right.length - lengthOfBadSuffix;
                        }
                        *suffixChars = MAX(0, n);
                    }
                    DLog(@"Using path %@", extendedPath);
                    return extendedPath;
                }
            }
            if (--iterationsBeforeQuitting == 0) {
                return nil;
            }
        }
    }
    return nil;
}

- (NSString *)columnAndLineNumberFromChunks:(NSArray<NSString *> *)afterChunks {
    NSString *suffix = [afterChunks componentsJoinedByString:@""];
    NSArray<NSString *> *regexes = @[ @"^(:\\d+)",
                                      @"^(\\[\\d+, ?\\d+])",
                                      @"^(\", line \\d+, column \\d+)",
                                      @"^(\\(\\d+, ?\\d+\\))"];
    for (NSString *regex in regexes) {
        NSString *value = [suffix stringByMatching:regex capture:1];
        if (value) {
            return value;
        }
    }
    return @"";
}

- (NSArray *)pathsFromPath:(NSString *)source byRemovingBadSuffixes:(NSArray *)badSuffixes {
    NSMutableArray *result = [NSMutableArray array];
    [result addObject:source];
    for (NSString *badSuffix in badSuffixes) {
        if ([source hasSuffix:badSuffix]) {
            NSString *stripped = [source substringToIndex:source.length - badSuffix.length];
            if (stripped.length) {
                [result addObject:stripped];
            }
        }
    }
    return result;
}

- (NSFileManager *)fileManager {
    return [NSFileManager defaultManager];
}

@end
