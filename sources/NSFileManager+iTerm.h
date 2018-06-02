//
//  NSFileManager+DirectoryLocations.h
//
//  Created by Matt Gallagher on 06 May 2010
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

// This code has been altered.

#import <Foundation/Foundation.h>

@interface NSFileManager (iTerm)

- (NSString *)legacyApplicationSupportDirectory;
- (NSString *)applicationSupportDirectory;

// Gives a symlink called ApplicationSupport because shebangs can't handle spaces and this breaks pyenv.
// Creates the symlink if it doesn't already exist
- (NSString *)applicationSupportDirectoryWithoutSpaces;
- (NSString *)applicationSupportDirectoryWithoutSpacesWithoutCreatingSymlink;

- (NSString *)temporaryDirectory;

- (NSString *)downloadsDirectory;

- (BOOL)directoryIsWritable:(NSString *)dir;

// Returns YES if the file exists on a local (non-network) filesystem.
- (BOOL)fileExistsAtPathLocally:(NSString *)filename
         additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkpaths;

- (BOOL)fileHasForbiddenPrefix:(NSString *)filename
        additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkpaths;

// Returns the path to the user's desktop.
- (NSString *)desktopDirectory;

// Filename holding the version number of iTerm2 that was last run. If iTerm2 is launched with
// this file as the file to open, then autolaunch scripts won't run and window restoration.
- (NSString *)versionNumberFilename;

// Directory where scripts live. These are loaded and added to a menu or auto-run at startup.
- (NSString *)scriptsPath;
- (NSString *)scriptsPathWithoutSpaces;

// Path to special auto-launch script that is run at startup.
- (NSString *)legacyAutolaunchScriptPath;  // applescript
- (NSString *)autolaunchScriptPath;  // scripting API

// Path to special file that, if it exists at launch time, suppresses autolaunch script and
// window restoration.
- (NSString *)quietFilePath;
- (BOOL)directoryEmpty:(NSString *)path;
- (BOOL)itemIsSymlink:(NSString *)path;
- (BOOL)itemIsDirectory:(NSString *)path;

@end
