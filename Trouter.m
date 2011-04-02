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


@implementation Trouter

- (Trouter *) init {
    self = [super init];
    [self determineEditor];
    fileManager = [[NSFileManager alloc] init];
    return self;
}

- (void) dealloc {
    [fileManager release];
    [super dealloc];
}

- (void) determineEditor {
    if ([self applicationExists: @"org.vim.MacVim"]) {
        editor = @"mvim";
    }
    else if ([self applicationExists: @"com.macromates.textmate"]) {
        editor = @"txmt";
    }
    else if ([self applicationExists: @"com.barebones.bbedit"]) {
        // BBedit suports txmt handler but doesn't have one of its own for some reason.
        editor = @"txmt";
    }
}

- (NSFileManager *) fileManager {
    return fileManager;
}

- (BOOL) applicationExists:(NSString *)bundle_id {
    return [self applicationExists:bundle_id path:nil];
}

- (BOOL) applicationExists:(NSString *)bundle_id path:(NSString **)path {
    CFURLRef appURL;
    OSStatus result = LSFindApplicationForInfo (
                                                kLSUnknownCreator,
                                                (CFStringRef)bundle_id,
                                                NULL,
                                                NULL,
                                                &appURL
                                                );
    
    if (appURL) {
        if (path != nil)
            *path = [(NSURL *)appURL path];
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

- (BOOL) isTextFile:(NSString *)path {
    BOOL ret = FALSE;
    MDItemRef item = MDItemCreate(kCFAllocatorDefault, (CFStringRef)path);
    CFTypeRef ref = MDItemCopyAttribute(item, CFSTR("kMDItemContentType"));

    if (ref) {
        if (UTTypeConformsTo(ref, CFSTR("public.text"))) {
            ret = TRUE;
        }
        CFRelease(ref);
    }

    if (item) CFRelease(item);
    return ret;
}

- (NSString *) getFullPath:(NSString *)path workingDirectory:(NSString *)workingDirectory lineNumber:(NSString **)lineNumber {
    if (!path || [path length] == 0)
        return nil;
    if (lineNumber != nil)
        *lineNumber = [path stringByMatching:@":(\\d+)" capture:1];
    path = [path stringByReplacingOccurrencesOfRegex:@":\\d+(?::.*)?$" withString:@""];

    if ([path substringToIndex:1] != @"/")
        path = [NSString stringWithFormat:@"%@/%@", workingDirectory, path];

    return path;
}


- (void) openPath:(NSString *)path workingDirectory:(NSString *)workingDirectory {
    BOOL isDirectory;
    NSString* lineNumber;

    path = [self getFullPath:path workingDirectory:workingDirectory lineNumber:&lineNumber];

    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory])
        return;

    if (lineNumber == nil)
        lineNumber = @"";

    if (isDirectory) {
        [[NSWorkspace sharedWorkspace] openFile:path];
        return;
    }

    if (editor && [self isTextFile: path]) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://open?url=file://%@&line=%@", editor, path, lineNumber, nil]];
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    [[NSWorkspace sharedWorkspace] openFile:path];
}

@end
