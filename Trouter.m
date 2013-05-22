// -*- mode:objc -*-
/*
 **  Trouter.h
 **
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

#import "Trouter.h"
#import "RegexKitLite/RegexKitLite.h"
#import "TrouterPrefsController.h"
#import "NSStringITerm.h"

@implementation Trouter

@synthesize prefs = prefs_;

- (Trouter *)init
{
    self = [super init];
    if (self) {
      fileManager = [[NSFileManager alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [fileManager release];
    [super dealloc];
}

- (NSFileManager *)fileManager
{
    return fileManager;
}

- (BOOL) isDirectory:(NSString *)path
{
    BOOL ret;
    [fileManager fileExistsAtPath:path isDirectory:&ret];
    return ret;
}

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

- (BOOL)file:(NSString *)path conformsToUTI:(NSString *)uti
{
    BOOL ret = FALSE;
    MDItemRef item = MDItemCreate(kCFAllocatorDefault, (CFStringRef)path);
    CFTypeRef ref = 0;
    if (item) {
      ref = MDItemCopyAttribute(item, CFSTR("kMDItemContentType"));
    }

    if (ref) {
        if (UTTypeConformsTo(ref, (CFStringRef) uti)) {
            ret = TRUE;
        }
        CFRelease(ref);
    }

    if (item) {
      CFRelease(item);
    }
    return ret;
}

- (NSString *)getFullPath:(NSString *)path
         workingDirectory:(NSString *)workingDirectory
               lineNumber:(NSString **)lineNumber
{
    NSString *origPath = path;
    // TODO(chendo): Move regex, define capture semants in config file/prefs
    if (!path || [path length] == 0) {
        return nil;
    }

    // strip various trailing characters that are unlikely to be part of the file name.
    path = [path stringByReplacingOccurrencesOfRegex:@"[.),:]$"
                                          withString:@""];

    if (lineNumber != nil) {
        *lineNumber = [path stringByMatching:@":(\\d+)" capture:1];
    }
    path = [[path stringByReplacingOccurrencesOfRegex:@":\\d*(?::.*)?$"
                                           withString:@""]
               stringByExpandingTildeInPath];
    if ([path rangeOfRegex:@"^/"].location == NSNotFound) {
        path = [NSString stringWithFormat:@"%@/%@", workingDirectory, path];
    }

    NSURL *url = [NSURL fileURLWithPath:path];

    // Resolve path by removing ./ and ../ etc
    path = [[url standardizedURL] path];

    if ([fileManager fileExistsAtPath:path]) {
        return path;
    }

    // If path doesn't exist and it starts with "a/" or "b/" (from `diff`).
    if ([origPath isMatchedByRegex:@"^[ab]/"]) {
        // strip the prefix off ...
        origPath = [origPath stringByReplacingOccurrencesOfRegex:@"^[ab]/"
                                                 withString:@""];

        // ... and calculate the full path again
        return [self getFullPath:origPath
                workingDirectory:workingDirectory
                      lineNumber:lineNumber];
    }

    return nil;
}

- (NSString *)editor
{
    if ([[prefs_ objectForKey:kTrouterActionKey] isEqualToString:kTrouterBestEditorAction]) {
        return [TrouterPrefsController bestEditor];
    } else if ([[prefs_ objectForKey:kTrouterActionKey] isEqualToString:kTrouterEditorAction]) {
        return [TrouterPrefsController schemeForEditor:[prefs_ objectForKey:kTrouterEditorKey]] ?
            [prefs_ objectForKey:kTrouterEditorKey] : nil;
    } else {
        return nil;
    }
}

- (BOOL)openFileInEditor:(NSString *)path lineNumber:(NSString *)lineNumber {
    if ([self editor]) {
        if ([[self editor] isEqualToString:kSublimeText2Identifier] ||
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
                        [NSTask launchedTaskWithLaunchPath:sublimeTextExecutable
                                                 arguments:[NSArray arrayWithObjects:sublimeTextExecutable, path, nil]];
                    }
                }
            }
        } else {
            path = [path stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
                                               @"%@://open?url=file://%@&line=%@",
                                               [TrouterPrefsController schemeForEditor:[self editor]],
                                               path, lineNumber, nil]];
            [[NSWorkspace sharedWorkspace] openURL:url];

        }
    }
    return YES;
}


- (BOOL)openPath:(NSString *)path
    workingDirectory:(NSString *)workingDirectory
    prefix:(NSString *)prefix
    suffix:(NSString *)suffix
{
    BOOL isDirectory;
    NSString* lineNumber = @"";

    path = [self getFullPath:path
            workingDirectory:workingDirectory
                  lineNumber:&lineNumber];


    if ([[prefs_ objectForKey:kTrouterActionKey] isEqualToString:kTrouterRawCommandAction]) {
        NSString *script = [prefs_ objectForKey:kTrouterTextKey];
        script = [script stringByReplacingBackreference:1
                                             withString:path ? [path stringWithEscapedShellCharacters] : @""];
            script = [script stringByReplacingBackreference:2
                                                 withString:lineNumber ? lineNumber : @""];
        script = [script stringByReplacingBackreference:3
                                             withString:[prefix stringWithEscapedShellCharacters]];
        script = [script stringByReplacingBackreference:4
                                             withString:[suffix stringWithEscapedShellCharacters]];
        script = [script stringByReplacingBackreference:5
                                             withString:[workingDirectory stringWithEscapedShellCharacters]];
        [[NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                  arguments:[NSArray arrayWithObjects:@"-c", script, nil]] waitUntilExit];
        return YES;
    }

    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        return NO;
    }

    if ([[prefs_ objectForKey:kTrouterActionKey] isEqualToString:kTrouterCommandAction]) {
        NSString *script = [prefs_ objectForKey:kTrouterTextKey];
        script = [script stringByReplacingBackreference:1 withString:path ? [path stringWithEscapedShellCharacters] : @""];
        script = [script stringByReplacingBackreference:2 withString:lineNumber ? lineNumber : @""];
        script = [script stringByReplacingBackreference:3 withString:[prefix stringWithEscapedShellCharacters]];
        script = [script stringByReplacingBackreference:4 withString:[suffix stringWithEscapedShellCharacters]];
        script = [script stringByReplacingBackreference:5 withString:[workingDirectory stringWithEscapedShellCharacters]];
        [[NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                  arguments:[NSArray arrayWithObjects:@"-c", script, nil]] waitUntilExit];
        return YES;
    }

    if (isDirectory) {
        [[NSWorkspace sharedWorkspace] openFile:path];
        return YES;
    }

    if ([[prefs_ objectForKey:kTrouterActionKey] isEqualToString:kTrouterUrlAction]) {
        NSString *url = [prefs_ objectForKey:kTrouterTextKey];
        url = [url stringByReplacingBackreference:1 withString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        url = [url stringByReplacingBackreference:2 withString:lineNumber];
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
        return YES;
    }

    if ([self editor] && [self isTextFile:path]) {
        return [self openFileInEditor: path lineNumber:lineNumber];
    }

    [[NSWorkspace sharedWorkspace] openFile:path];
    return YES;
}

@end
