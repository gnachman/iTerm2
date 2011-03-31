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
}

- (BOOL) applicationExists: (CFStringRef)bundle_id {
    CFURLRef appURL;
    OSStatus result = LSFindApplicationForInfo (
                                                kLSUnknownCreator,        
                                                bundle_id,  
                                                NULL,                     
                                                NULL,                     
                                                &appURL
                                                );
    CFRelease(appURL);
    switch (result) {
        case noErr:
            return true;
        case kLSApplicationNotFoundErr:
            return false;
        default:
            return false;
    }
}

- (void) routePath:(NSString *)path {
    BOOL isDirectory;
    NSString* lineNumber;
    
    lineNumber = [path stringByMatching:@":(\\d+)" capture:1];
    path = [path stringByReplacingOccurrencesOfRegex:@":\\d+(?::.+)?$" withString:@""];
    
    if (lineNumber == nil)
        lineNumber = @"";
    
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory])
        return;
    
    if (isDirectory) {
        [[NSWorkspace sharedWorkspace] openFile:path];
        return;
    }
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://open?url=file://%@&line=%@", editor, path, lineNumber, nil]];
        
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
