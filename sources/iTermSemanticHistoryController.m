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
#import "NSURL+iTerm.h"
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

- (BOOL)fileHasForbiddenPrefix:(NSString *)path {
    return [self.fileManager fileHasForbiddenPrefix:path
                             additionalNetworkPaths:[[iTermAdvancedSettingsModel pathsToIgnore] componentsSeparatedByString:@","]];
}

- (NSString *)getFullPath:(NSString *)path
         workingDirectory:(NSString *)workingDirectory
               lineNumber:(NSString **)lineNumber
             columnNumber:(NSString **)columnNumber {
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
    if (columnNumber != nil) {
        *columnNumber = [path stringByMatching:@":(\\d+):(\\d+)" capture:2];
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
    // If path doesn't exist and it starts with "a/" or "b/" (from `diff`).
    if ([origPath isMatchedByRegex:@"^[ab]/"]) {
        DLog(@"  Treating as diff path");
        // strip the prefix off ...
        origPath = [origPath stringByReplacingOccurrencesOfRegex:@"^[ab]/"
                                                 withString:@""];

        // ... and calculate the full path again
        return [self getFullPath:origPath
                workingDirectory:workingDirectory
                      lineNumber:lineNumber
                    columnNumber:columnNumber];
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
            // use Applescript because it won't open the file to a particular line number.
            [self launchAppWithBundleIdentifier:kVSCodeIdentifier path:path];
        }
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
              kVSCodeIdentifier,
              kSublimeText2Identifier,
              kSublimeText3Identifier,
              kMacVimIdentifier,
              kTextmateIdentifier,
              kTextmate2Identifier,
              kBBEditIdentifier ];
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

- (BOOL)openPath:(NSString *)path
    workingDirectory:(NSString *)workingDirectory
       substitutions:(NSDictionary *)substitutions {
    DLog(@"openPath:%@ workingDirectory:%@ substitutions:%@", path, workingDirectory, substitutions);
    BOOL isDirectory;
    NSString *lineNumber = @"";
    NSString *columnNumber = @"";

    BOOL isRawAction = [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
    if (!isRawAction) {
        path = [self getFullPath:path workingDirectory:workingDirectory
                      lineNumber:&lineNumber
                    columnNumber:&columnNumber];
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
    BOOL workingDirectoryIsOk = [self fileExistsAtPathLocally:workingDirectory];
    if (!workingDirectoryIsOk) {
        DLog(@"Working directory %@ is a network share or doesn't exist. Not using it for context.",
             workingDirectory);
    }

    DLog(@"Brute force path from prefix <<%@>>, suffix <<%@>> directory=%@",
         beforeStringIn, afterStringIn, workingDirectory);

    // The parens here cause "Foo bar" to become {"Foo", " ", "bar"} rather than {"Foo", "bar"}.
    // Also, there is some kind of weird bug in regexkit. If you do [[beforeChunks mutableCopy] autorelease]
    // then the items in the array get over-released.
    NSString *const kSplitRegex = @"([\t ()])";
    NSArray *beforeChunks = [beforeStringIn componentsSeparatedByRegex:kSplitRegex];
    NSArray *afterChunks = [afterStringIn componentsSeparatedByRegex:kSplitRegex];
    DLog(@"before chunks=%@", beforeChunks);
    DLog(@"after chunks=%@", afterChunks);

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
                    exists = ([self getFullPath:modifiedPossiblePath
                               workingDirectory:workingDirectory
                                     lineNumber:NULL
                                   columnNumber:NULL] != nil);
                }
                if (exists) {
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
                        NSInteger lengthOfBadSuffix = trimmedPath.length - modifiedPossiblePath.length;
                        if (trimWhitespace) {
                            *suffixChars = [[right stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length] - lengthOfBadSuffix;
                        } else {
                            *suffixChars = right.length - lengthOfBadSuffix;
                        }
                    }
                    DLog(@"Using path %@", modifiedPossiblePath);
                    return modifiedPossiblePath;
                }
            }
            if (--iterationsBeforeQuitting == 0) {
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
