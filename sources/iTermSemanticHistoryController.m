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
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"

NSString *const kSemanticHistoryPathSubstitutionKey = @"semanticHistory.path";
NSString *const kSemanticHistoryPrefixSubstitutionKey = @"semanticHistory.prefix";
NSString *const kSemanticHistorySuffixSubstitutionKey = @"semanticHistory.suffix";
NSString *const kSemanticHistoryWorkingDirectorySubstitutionKey = @"semanticHistory.workingDirectory";

@implementation iTermSemanticHistoryController

@synthesize prefs = prefs_;
@synthesize delegate = delegate_;

- (BOOL)fileExistsAtPathLocally:(NSString *)path {
    return [self.fileManager fileExistsAtPathLocally:path
                              additionalNetworkPaths:[[iTermAdvancedSettingsModel pathsToIgnore] componentsSeparatedByString:@","]];
}

- (NSString *)getFullPath:(NSString *)path
         workingDirectory:(NSString *)workingDirectory
               lineNumber:(NSString **)lineNumber {
    DLog(@"Check if %@ is a valid path in %@", path, workingDirectory);
    NSString *origPath = path;
    // TODO(chendo): Move regex, define capture semantics in config file/prefs
    if (!path || [path length] == 0) {
        DLog(@"  no: it is empty");
        return nil;
    }

    // If it's in any form of bracketed delimiters, strip them
    path = [path stringByRemovingEnclosingBrackets];

    // strip various trailing characters that are unlikely to be part of the file name.
    path = [path stringByReplacingOccurrencesOfRegex:@"[.),:]$"
                                          withString:@""];
    DLog(@" Strip trailing chars, leaving %@", path);

    if (lineNumber != nil) {
        *lineNumber = [path stringByMatching:@":(\\d+)" capture:1];
    }
    path = [[path stringByReplacingOccurrencesOfRegex:@":\\d*(?::.*)?$"
                                           withString:@""]
               stringByExpandingTildeInPath];
    DLog(@"  Strip line number suffix leaving %@", path);
    if ([path length] == 0) {
        // Everything was stripped out, meaning we'd try to open the working directory.
        return nil;
    }
    if ([path rangeOfRegex:@"^/"].location == NSNotFound) {
        path = [workingDirectory stringByAppendingPathComponent:path];
        DLog(@"  Prepend working directory, giving %@", path);
    }

    NSURL *url = [NSURL fileURLWithPath:path];

    // Resolve path by removing ./ and ../ etc
    path = [[url standardizedURL] path];
    DLog(@"  Standardized path is %@", path);

    if ([self fileExistsAtPathLocally:path]) {
        DLog(@"    YES: A file exists at %@", path);
        return path;
    }

    // If path doesn't exist and it starts with "a/" or "b/" (from `diff`).
    if ([origPath isMatchedByRegex:@"^[ab]/"]) {
        DLog(@"  Treating as diff path");
        // strip the prefix off ...
        origPath = [origPath stringByReplacingOccurrencesOfRegex:@"^[ab]/"
                                                 withString:@""];

        // ... and calculate the full path again
        return [self getFullPath:origPath
                workingDirectory:workingDirectory
                      lineNumber:lineNumber];
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
    NSString *bundlePath =
        [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleIdentifier];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *executable = [bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    executable = [executable stringByAppendingPathComponent:
                            [bundle objectForInfoDictionaryKey:(id)kCFBundleExecutableKey]];
    if (bundle && executable && path) {
        DLog(@"Launch %@: %@ %@", bundleIdentifier, executable, path);
        [self launchTaskWithPath:executable arguments:@[ path ] wait:NO];
    }
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
            // use Applescript because it won't open the file to a particular line number.
            [self launchAppWithBundleIdentifier:bundleId path:path];
        }
    }
}

+ (NSArray *)bundleIdsThatSupportOpeningToLineNumber {
    return @[ kAtomIdentifier,
              kSublimeText2Identifier,
              kSublimeText3Identifier,
              kMacVimIdentifier,
              kTextmateIdentifier,
              kTextmate2Identifier,
              kBBEditIdentifier ];
}

- (void)openFile:(NSString *)path
    inEditorWithBundleId:(NSString *)identifier
          lineNumber:(NSString *)lineNumber {
    if (identifier) {
        DLog(@"openFileInEditor. editor=%@", [self preferredEditorIdentifier]);
        if ([identifier isEqualToString:kAtomIdentifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            [self launchAtomWithPath:path];
        } else if ([identifier isEqualToString:kSublimeText2Identifier] ||
                   [identifier isEqualToString:kSublimeText3Identifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            NSString *bundleId;
            if ([identifier isEqualToString:kSublimeText3Identifier]) {
                bundleId = kSublimeText3Identifier;
            } else {
                bundleId = kSublimeText2Identifier;
            }

            [self launchSublimeTextWithBundleIdentifier:bundleId path:path];
        } else {
            path = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
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

- (void)openFileInEditor:(NSString *)path lineNumber:(NSString *)lineNumber {
    [self openFile:path inEditorWithBundleId:[self preferredEditorIdentifier] lineNumber:lineNumber];
}

- (BOOL)canOpenPath:(NSString *)path workingDirectory:(NSString *)workingDirectory {
    NSString *fullPath = [self getFullPath:path
                          workingDirectory:workingDirectory
                                lineNumber:NULL];
    return [self.fileManager fileExistsAtPath:fullPath];
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

- (BOOL)openPath:(NSString *)path
    workingDirectory:(NSString *)workingDirectory
       substitutions:(NSDictionary *)substitutions {
    DLog(@"openPath:%@ workingDirectory:%@ substitutions:%@", path, workingDirectory, substitutions);
    BOOL isDirectory;
    NSString *lineNumber = @"";

    BOOL isRawAction = [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
    if (!isRawAction) {
        path = [self getFullPath:path workingDirectory:workingDirectory lineNumber:&lineNumber];
        DLog(@"Not a raw action. New path is %@, line number is %@", path, lineNumber);
    }

    NSString *script = [prefs_ objectForKey:kSemanticHistoryTextKey];
    NSMutableDictionary *augmentedSubs = [[substitutions mutableCopy] autorelease];
    augmentedSubs[@"1"] = path ? [path stringWithEscapedShellCharacters] : @"";
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
        DLog(@"Launch coproress with script %@", script);
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
                [augmentedSubs[key] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
        url = [url stringByReplacingVariableReferencesWithVariables:augmentedSubs];
        DLog(@"Open url %@", url);
        [self openURL:[NSURL URLWithString:url]];
        return YES;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryEditorAction] &&
        [self preferredEditorIdentifier]) {
        // Action is to open in a specific editor, so open it in the editor.
        [self openFileInEditor:path lineNumber:lineNumber];
        return YES;
    }

    if (lineNumber) {
        NSString *appBundleId = [self bundleIdForDefaultAppForFile:path];
        if ([self canOpenFileWithLineNumberUsingEditorWithBundleId:appBundleId]) {
            DLog(@"A line number is present and I know how to open this file to the line number using %@. Do so.",
                 appBundleId);
            [self openFile:path inEditorWithBundleId:appBundleId lineNumber:lineNumber];
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
        return NO;
    }

    NSBundle *appBundle = [NSBundle bundleWithURL:appUrl];
    if (!appBundle) {
        return NO;
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
                                 trimWhitespace:(BOOL)trimWhitespace {
    BOOL workingDirectoryIsOk = [self fileExistsAtPathLocally:workingDirectory];
    if (!workingDirectoryIsOk) {
        DLog(@"Working directory %@ is a network share or doesn't exist. Not using it for context.",
             workingDirectory);
    }

    NSMutableString *beforeString = [[beforeStringIn mutableCopy] autorelease];
    NSMutableString *afterString = [[afterStringIn mutableCopy] autorelease];

    // Remove escaping slashes
    NSString *removeEscapingSlashes = @"\\\\([ \\(\\[\\]\\\\)])";

    DLog(@"Brute force path from prefix <<%@>>, suffix <<%@>> directory=%@",
         beforeString, afterString, workingDirectory);

    [beforeString replaceOccurrencesOfRegex:removeEscapingSlashes withString:@"$1"];
    [afterString replaceOccurrencesOfRegex:removeEscapingSlashes withString:@"$1"];
    beforeString = [[beforeString copy] autorelease];
    // The parens here cause "Foo bar" to become {"Foo", " ", "bar"} rather than {"Foo", "bar"}.
    // Also, there is some kind of weird bug in regexkit. If you do [[beforeChunks mutableCopy] autorelease]
    // then the items in the array get over-released.
    NSString *const kSplitRegex = @"([\t ()])";
    NSArray *beforeChunks = [beforeString componentsSeparatedByRegex:kSplitRegex];
    NSArray *afterChunks = [afterString componentsSeparatedByRegex:kSplitRegex];

    // If the before/after string didn't produce any chunks, allow the other
    // half to stand alone.
    if (!beforeChunks.count) {
        beforeChunks = @[ @"" ];
    }
    if (!afterChunks.count) {
        afterChunks = @[ @"" ];
    }

    NSMutableString *left = [NSMutableString string];
    // Bail after 100 iterations if nothing is still found.
    int limit = 100;

    NSMutableSet *paths = [NSMutableSet set];

    DLog(@"before chunks=%@", beforeChunks);
    DLog(@"after chunks=%@", afterChunks);

    // Some programs will thoughtlessly print a filename followed by some silly suffix.
    // We'll try versions with and without a questionable suffix. The version
    // with the suffix is always preferred if it exists.
    NSArray *questionableSuffixes = @[ @"!", @"?", @".", @",", @";", @":", @"...", @"…" ];
    NSCharacterSet *whitespaceCharset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (int i = [beforeChunks count]; i >= 0; i--) {
        NSString *beforeChunk = @"";
        if (i < [beforeChunks count]) {
            beforeChunk = [beforeChunks objectAtIndex:i];
        }

        [left insertString:beforeChunk atIndex:0];
        NSMutableString *possiblePath = [NSMutableString stringWithString:left];

        // Do not search more than 10 chunks forward to avoid starving leftward search.
        for (int j = 0; j < [afterChunks count] && j < 10; j++) {
            [possiblePath appendString:afterChunks[j]];
            NSString *trimmedPath;
            if (trimWhitespace) {
                trimmedPath = [possiblePath stringByTrimmingCharactersInSet:whitespaceCharset];
            } else {
                trimmedPath = possiblePath;
            }
            if ([paths containsObject:[NSString stringWithString:trimmedPath]]) {
                continue;
            }
            [paths addObject:[[trimmedPath copy] autorelease]];

            for (NSString *modifiedPossiblePath in [self pathsFromPath:trimmedPath byRemovingBadSuffixes:questionableSuffixes]) {
                BOOL exists = NO;
                if (workingDirectoryIsOk || [modifiedPossiblePath hasPrefix:@"/"]) {
                    exists = ([self getFullPath:modifiedPossiblePath workingDirectory:workingDirectory lineNumber:NULL] != nil);
                }
                if (exists) {
                    if (charsTakenFromPrefixPtr) {
                        if (trimWhitespace) {
                            if ([afterChunks[j] length] == 0) {
                                // trimmedPath is trim(left + afterChunks[j]). If afterChunks[j] is empty
                                // then we don't want to count trailing whitespace from left in the chars
                                // taken from prefix.
                                *charsTakenFromPrefixPtr = [[left stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length];
                            } else {
                                *charsTakenFromPrefixPtr = left.length;
                            }
                        } else {
                            *charsTakenFromPrefixPtr = left.length;
                        }
                    }
                    DLog(@"Using path %@", modifiedPossiblePath);
                    return modifiedPossiblePath;
                }
            }
            if (--limit == 0) {
                return nil;
            }
        }
    }
    return nil;
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
