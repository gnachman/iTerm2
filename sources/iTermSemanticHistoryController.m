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
#import "iTermSemanticHistoryPrefsController.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite/RegexKitLite.h"

NSString *const kSemanticHistoryPathSubstitutionKey = @"semanticHistory.path";
NSString *const kSemanticHistoryPrefixSubstitutionKey = @"semanticHistory.prefix";
NSString *const kSemanticHistorySuffixSubstitutionKey = @"semanticHistory.suffix";
NSString *const kSemanticHistoryWorkingDirectorySubstitutionKey = @"semanticHistory.workingDirectory";

@implementation iTermSemanticHistoryController

@synthesize prefs = prefs_;
@synthesize delegate = delegate_;

- (BOOL)isTextFile:(NSString *)path
{
    // TODO(chendo): link in the "magic" library from file instead of calling it.
    NSTask *task = [[[NSTask alloc] init] autorelease];
    NSPipe *myPipe = [NSPipe pipe];
    NSFileHandle *file = [myPipe fileHandleForReading];

    [task setStandardOutput:myPipe];
    [task setLaunchPath:@"/usr/bin/file"];
    [task setArguments:[NSArray arrayWithObject:path]];
    [task launch];
    [task waitUntilExit];

    NSString *output = [[NSString alloc] initWithData:[file readDataToEndOfFile]
                                             encoding:NSUTF8StringEncoding];

    BOOL ret = ([output rangeOfRegex:@"\\btext\\b"].location != NSNotFound);
    [output release];
    return ret;
}

- (NSString *)getFullPath:(NSString *)path
         workingDirectory:(NSString *)workingDirectory
               lineNumber:(NSString **)lineNumber
{
    DLog(@"Check if %@ is a valid path in %@", path, workingDirectory);
    NSString *origPath = path;
    // TODO(chendo): Move regex, define capture semants in config file/prefs
    if (!path || [path length] == 0) {
        DLog(@"  no: it is empty");
        return nil;
    }

    // If it's in parens, strip them.
    if (path.length > 2 && [path characterAtIndex:0] == '(' && [path hasSuffix:@")"]) {
        path = [path substringWithRange:NSMakeRange(1, path.length - 2)];
        DLog(@" Strip parens, leaving %@", path);
    }

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
        path = [NSString stringWithFormat:@"%@/%@", workingDirectory, path];
        DLog(@"  Prepend working directory, giving %@", path);
    }

    NSURL *url = [NSURL fileURLWithPath:path];

    // Resolve path by removing ./ and ../ etc
    path = [[url standardizedURL] path];
    DLog(@"  Standardized path is %@", path);

    if ([[NSFileManager defaultManager] fileExistsAtPathLocally:path]) {
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

- (NSString *)editor
{
    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryBestEditorAction]) {
        return [iTermSemanticHistoryPrefsController bestEditor];
    } else if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryEditorAction]) {
        return [iTermSemanticHistoryPrefsController schemeForEditor:prefs_[kSemanticHistoryEditorKey]] ?
            prefs_[kSemanticHistoryEditorKey] : nil;
    } else {
        return nil;
    }
}

- (BOOL)openFileInEditor:(NSString *)path lineNumber:(NSString *)lineNumber {
    if ([self editor]) {
        DLog(@"openFileInEditor. editor=%@", [self editor]);
        if ([[self editor] isEqualToString:kAtomIdentifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            NSString *bundlePath =
                [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.github.atom"];
            NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
            NSString *executable = [NSString stringWithFormat:@"%@/Contents/MacOS/%@",
                                    bundlePath,
                                    [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"]];
            if (bundle && executable) {
                DLog(@"Launch Atom %@ %@ %@", executable, executable, path);
                [NSTask launchedTaskWithLaunchPath:executable arguments:@[ executable, path ]];
            }
        } else if ([[self editor] isEqualToString:kSublimeText2Identifier] ||
                   [[self editor] isEqualToString:kSublimeText3Identifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }

            NSString *bundlePath;
            if ([[self editor] isEqualToString:kSublimeText3Identifier]) {
                bundlePath = [[NSWorkspace sharedWorkspace]
                                 absolutePathForAppBundleWithIdentifier:@"com.sublimetext.3"];
            } else {
                bundlePath = [[NSWorkspace sharedWorkspace]
                                 absolutePathForAppBundleWithIdentifier:@"com.sublimetext.2"];
            }
            if (bundlePath) {
                NSString *sublExecutable = [NSString stringWithFormat:@"%@/Contents/SharedSupport/bin/subl",
                                            bundlePath];
                if ([[NSFileManager defaultManager] fileExistsAtPath:sublExecutable]) {
                    DLog(@"Launch sublime text %@ %@", sublExecutable, path);
                    [NSTask launchedTaskWithLaunchPath:sublExecutable
                                             arguments:[NSArray arrayWithObjects:path, nil]];
                } else {
                    // This isn't as good as opening "subl" because it always opens a new instance
                    // of the app but it's the OS-sanctioned way of running Sublimetext.  We can't
                    // use Applescript because it won't open the file to a particular line number.
                    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
                    NSString *sublimeTextExecutable = [NSString stringWithFormat:@"%@/Contents/MacOS/%@",
                                                       bundlePath,
                                                       [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"]];
                    if (bundle && sublimeTextExecutable) {
                        DLog(@"Launch sublime text %@ %@ %@", sublimeTextExecutable, sublimeTextExecutable, path);
                        [NSTask launchedTaskWithLaunchPath:sublimeTextExecutable
                                                 arguments:[NSArray arrayWithObjects:sublimeTextExecutable, path, nil]];
                    }
                }
            }
        } else {
            path = [path stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
                                               @"%@://open?url=file://%@&line=%@",
                                               [iTermSemanticHistoryPrefsController schemeForEditor:[self editor]],
                                               path, lineNumber, nil]];
            DLog(@"Open url %@", url);
            [[NSWorkspace sharedWorkspace] openURL:url];

        }
    }
    return YES;
}

- (BOOL)canOpenPath:(NSString *)path workingDirectory:(NSString *)workingDirectory
{
    NSString *fullPath = [self getFullPath:path
                          workingDirectory:workingDirectory
                                lineNumber:NULL];
    return [[NSFileManager defaultManager] fileExistsAtPath:fullPath];
}

- (BOOL)activatesOnAnyString {
    return [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
}

- (BOOL)openPath:(NSString *)path
    workingDirectory:(NSString *)workingDirectory
       substitutions:(NSDictionary *)substitutions {
    DLog(@"openPath:%@ workingDirectory:%@ substitutions:%@",
         path, workingDirectory, substitutions);
    BOOL isDirectory;
    NSString* lineNumber = @"";

    BOOL isRawAction = [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
    if (!isRawAction) {
        path = [self getFullPath:path workingDirectory:workingDirectory lineNumber:&lineNumber];
        DLog(@"Not a raw action. New path is %@, line number is %@", path, lineNumber);
    }

    NSString *script = [prefs_ objectForKey:kSemanticHistoryTextKey];
    script = [script stringByReplacingBackreference:1 withString:path ? [path stringWithEscapedShellCharacters] : @""];
    script = [script stringByReplacingBackreference:2 withString:lineNumber ? lineNumber : @""];
    script = [script stringByReplacingBackreference:3 withString:substitutions[kSemanticHistoryPrefixSubstitutionKey]];
    script = [script stringByReplacingBackreference:4 withString:substitutions[kSemanticHistorySuffixSubstitutionKey]];
    script = [script stringByReplacingBackreference:5 withString:substitutions[kSemanticHistoryWorkingDirectorySubstitutionKey]];
    script = [script stringByReplacingVariableReferencesWithVariables:substitutions];

    DLog(@"After escaping backrefs, script is %@", script);

    if (isRawAction) {
        DLog(@"Launch raw action: /bin/sh -c %@", script);
        [[NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                  arguments:[NSArray arrayWithObjects:@"-c", script, nil]] waitUntilExit];
        return YES;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
        DLog(@"No file exists at %@, not running semantic history", path);
        return NO;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryCommandAction]) {
        DLog(@"Running /bin/sh -c %@", script);
        [[NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                  arguments:[NSArray arrayWithObjects:@"-c", script, nil]] waitUntilExit];
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
        [[NSWorkspace sharedWorkspace] openFile:path];
        return YES;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryUrlAction]) {
        NSString *url = prefs_[kSemanticHistoryTextKey];
        url = [url stringByReplacingBackreference:1 withString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        url = [url stringByReplacingBackreference:2 withString:lineNumber];
        DLog(@"Open url %@", url);
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
        return YES;
    }

    if ([self editor] && [self isTextFile:path]) {
        if (![self defaultAppForFileIsEditor:path]) {
            DLog(@"Default app for %@ is NOT an editor, so open it in an editor", path);
            return [self openFileInEditor:path lineNumber:lineNumber];
        } else {
            DLog(@"Default app for %@ is an editor so just open it", path);
        }
    }

    [[NSWorkspace sharedWorkspace] openFile:path];
    return YES;
}

- (BOOL)defaultAppForFileIsEditor:(NSString *)file {
    NSURL *fileUrl = [NSURL fileURLWithPath:file];
    NSURL *appUrl = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:fileUrl];
    if (!appUrl) {
        return NO;
    }

    NSBundle *appBundle = [NSBundle bundleWithURL:appUrl];
    if (!appBundle) {
        return NO;
    }
    NSString *bundleId = [appBundle bundleIdentifier];
    return [iTermSemanticHistoryPrefsController bundleIdIsEditor:bundleId];
}

- (NSString *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                         suffix:(NSString *)afterStringIn
                               workingDirectory:(NSString *)workingDirectory
                           charsTakenFromPrefix:(int *)charsTakenFromPrefixPtr {
    BOOL workingDirectoryIsOk = [[NSFileManager defaultManager] fileExistsAtPathLocally:workingDirectory];
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
    // Also, there is some kind of weird bug in regexkit. If you do [[beforeChunks mutableCopy] autoRelease]
    // then the items in the array get over-released.
    NSArray *beforeChunks = [beforeString componentsSeparatedByRegex:@"([\t ])"];
    NSArray *afterChunks = [afterString componentsSeparatedByRegex:@"([\t ])"];
    
    // If the before/after string didn't produce any chunks, allow the other
    // half to stand alone.
    if (!beforeChunks.count) {
        beforeChunks = [beforeChunks arrayByAddingObject:@""];
    }
    if (!afterChunks.count) {
        afterChunks = [afterChunks arrayByAddingObject:@""];
    }
    
    NSMutableString *left = [NSMutableString string];
    // Bail after 100 iterations if nothing is still found.
    int limit = 100;

    NSMutableSet *paths = [NSMutableSet set];
    NSMutableSet *befores = [NSMutableSet set];

    DLog(@"before chunks=%@", beforeChunks);
    DLog(@"after chunks=%@", afterChunks);

    // Some programs will thoughtlessly print a filename followed by some silly suffix.
    // We'll try versions with and without a questionable suffix. The version
    // with the suffix is always preferred if it exists.
    NSArray *questionableSuffixes = @[ @"!", @"?", @".", @",", @";", @":", @"...", @"…" ];

    for (int i = [beforeChunks count]; i >= 0; i--) {
        NSString *beforeChunk = @"";
        if (i < [beforeChunks count]) {
            beforeChunk = [beforeChunks objectAtIndex:i];
        }

        if ([befores containsObject:beforeChunk]) {
            continue;
        }
        [befores addObject:beforeChunk];
        
        [left insertString:beforeChunk atIndex:0];
        NSMutableString *possiblePath = [NSMutableString stringWithString:left];
        
        // Do not search more than 10 chunks forward to avoid starving leftward search.
        for (int j = 0; j < [afterChunks count] && j < 10; j++) {
            [possiblePath appendString:[afterChunks objectAtIndex:j]];
            if ([paths containsObject:[NSString stringWithString:possiblePath]]) {
                continue;
            }
            [paths addObject:[[possiblePath copy] autorelease]];

            for (NSString *modifiedPossiblePath in [self pathsFromPath:possiblePath byRemovingBadSuffixes:questionableSuffixes]) {
                BOOL exists = NO;
                if (workingDirectoryIsOk || [modifiedPossiblePath hasPrefix:@"/"]) {
                    exists = ([self getFullPath:modifiedPossiblePath workingDirectory:workingDirectory lineNumber:NULL] != nil);
                }
                if (exists) {
                    if (charsTakenFromPrefixPtr) {
                        *charsTakenFromPrefixPtr = left.length;
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

@end
