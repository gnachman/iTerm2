// -*- mode:objc -*-
/*
 **  TRouter.h
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

#import "TRouter.h"
#import "RegexKitLite/RegexKitLite.h"


@implementation TRouter

- (TRouter *)init
{
    self = [super init];
    if (self) {
      [self determineEditor];
      fileManager = [[NSFileManager alloc] init];
      externalScript = [[NSUserDefaults standardUserDefaults] stringForKey:@"SemanticHistoryHandler"];
    }
    return self;
}

- (void)dealloc
{
    [fileManager release];
    [super dealloc];
}

- (void)determineEditor
{
    // TODO: Move this into a plist file/prefs
    if ([self applicationExists:@"org.vim.MacVim"]) {
        editor = @"mvim";
    } else if ([self applicationExists:@"com.macromates.textmate"]) {
        editor = @"txmt";
    } else if ([self applicationExists:@"com.barebones.bbedit"]) {
        // BBedit suports txmt handler but doesn't have one of its own for some reason.
        editor = @"txmt";
    }
}

- (NSFileManager *)fileManager
{
    return fileManager;
}

- (BOOL)applicationExists:(NSString *)bundle_id
{
    return [self applicationExists:bundle_id path:nil];
}

- (BOOL)applicationExists:(NSString *)bundle_id path:(NSString **)path
{
    CFURLRef appURL = nil;
    OSStatus result = LSFindApplicationForInfo(kLSUnknownCreator,
                                               (CFStringRef)bundle_id,
                                               NULL,
                                               NULL,
                                               &appURL);

    if (appURL) { 
        if (path != nil) {
            *path = [(NSURL *)appURL path];
        }
        CFRelease(appURL);
    }

    switch (result) {
        case noErr:
            return true;
        case kLSApplicationNotFoundErr:
            return false;
        default:
            return false;
    }
}

- (BOOL) isDirectory:(NSString *)path
{
    BOOL ret;
    [fileManager fileExistsAtPath:path isDirectory:&ret];
    return ret;
}

- (BOOL)isTextFile:(NSString *)path
{
    // TODO: link in the "magic" library from file instead of calling it.
    NSTask *task = [[NSTask alloc] init];
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
    // TODO: Move regex, define capture semants in config file/prefs
    if (!path || [path length] == 0) {
        return nil;
    }
    if (lineNumber != nil) {
        *lineNumber = [path stringByMatching:@":(\\d+)" capture:1];
    }
    path = [path stringByReplacingOccurrencesOfRegex:@":\\d+(?::.*)?$"
                                          withString:@""];

    if ([path rangeOfRegex:@"^/"].location == NSNotFound) {
        path = [NSString stringWithFormat:@"%@/%@", workingDirectory, path];
    }

    NSURL *url = [NSURL fileURLWithPath:path];

    // Resolve path by removing ./ and ../ etc
    path = [[url standardizedURL] path];

    return path;
}


- (BOOL)openPath:(NSString *)path workingDirectory:(NSString *)workingDirectory
{
    BOOL isDirectory;
    NSString* lineNumber;

    path = [self getFullPath:path
            workingDirectory:workingDirectory
                  lineNumber:&lineNumber];

    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        return NO;
    }

    if (lineNumber == nil) {
        lineNumber = @"";
    }

    if (externalScript) {
        [NSTask launchedTaskWithLaunchPath:externalScript
                                 arguments:[NSArray arrayWithObjects:path, lineNumber, nil]];
        return YES;
    }

    if (isDirectory) {
        [[NSWorkspace sharedWorkspace] openFile:path];
        return YES;
    }

    if (editor && [self isTextFile:path]) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
                                     @"%@://open?url=file://%@&line=%@", editor, path, lineNumber, nil]];
        [[NSWorkspace sharedWorkspace] openURL:url];
        return YES;
    }

    [[NSWorkspace sharedWorkspace] openFile:path];
    return YES;
}

@end
