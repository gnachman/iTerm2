/*
 **  iTermSemanticHistoryController.h
 **
 **  Copyright (c) 2011
 **
 **  Author: Jack Chen (chendo)
 **
 **  Project: iTerm
 **
 **  Description: Semantic History
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

#import <Foundation/Foundation.h>

// Keys for substitutions of openPath:workingDirectory:substitutions:.
extern NSString *const kSemanticHistoryPathSubstitutionKey;
extern NSString *const kSemanticHistoryPrefixSubstitutionKey;
extern NSString *const kSemanticHistorySuffixSubstitutionKey;
extern NSString *const kSemanticHistoryWorkingDirectorySubstitutionKey;

@protocol iTermSemanticHistoryControllerDelegate <NSObject>
- (void)semanticHistoryLaunchCoprocessWithCommand:(NSString *)command;
@end

@interface iTermSemanticHistoryController : NSObject

@property (nonatomic, copy) NSDictionary *prefs;
@property (nonatomic, assign) id<iTermSemanticHistoryControllerDelegate> delegate;
@property (nonatomic, readonly) BOOL activatesOnAnyString;  // Doesn't have to be a real file?

// Given a possibly relative |path| and |workingDirectory|, returns the absolute path. If |path|
// includes a line number then *lineNumber will be filled in with it. Files on network shares are
// rejected.
- (NSString *)getFullPath:(NSString *)path
         workingDirectory:(NSString *)workingDirectory
               lineNumber:(NSString **)lineNumber;

// Given a relative |path| (which may include a :line number) and a |workingDirectory|, returns
// whether it is openable. See notes on getFullPath:workingDirectory:lineNumber:.
- (BOOL)canOpenPath:(NSString *)path workingDirectory:(NSString *)workingDirectory;

// Opens the file at the relative |path| (which may include :lineNumber) in |workingDirectory|.
// The |substitutions| dictionary is used to expand \references in the command to run (gotten from
// self.prefs[kSemanticHistoryTextKey]) as follows:
//
// \1 -> path
// \2 -> line number
// \3 -> substitutions[kSemanticHistoryPrefixSubstitutionKey]
// \4 -> substitutions[kSemanticHistorySuffixSubstitutionKey]
// \5 -> substitutions[kSemanticHistoryWorkingDirectorySubstitutionKey]
// \(key) -> substitutions[key]
//
// Returns YES if the file was opened, NO if it could not be opened.
- (BOOL)openPath:(NSString *)path
        workingDirectory:(NSString *)workingDirectory
           substitutions:(NSDictionary *)substitutions;

// Do a brute force search by putting together suffixes of beforeString with prefixes of afterString
// to find an existing file in |workingDirectory|. |charsSTakenFromPrefixPtr| will be filled in with
// the number of characters from beforeString used.
//
// For example:
//   [semanticHistoryController pathOfExistingFileFoundWithPrefix:@"cat et"
//                                                         suffix:@"c/passwd > /dev/null"
//                                               workingDirectory:@"/"
//                                           charsTakenFromPrefix:&n
//                                                 trimWhitespace:NO]
// will return @"etc/passwd". *n will be set to 2.
//
// Note that the result may be a relative path. To get the full path,
// use getFullPath:workingDirectory:lineNumber.
//
// Furthermore, the result may be decorated. For example:
//   [semanticHistoryController pathOfExistingFileFoundWithPrefix:@"at Object.<anonymous> (/priva"
//                                                         suffix:@"te/tmp/test_iterm_node.js:1:69)"
//                                               workingDirectory:@"/"
//                                           charsTakenFromPrefix:&n
//                                                 trimWhitespace:NO]
//
// Will return "(/private/tmp/test_iterm_node.js:1:60)". It is suitable to pass this to
// getFullPath:workingDirectory:lineNumber:, which will remove the parens and extract the line
// number, returning just the filename component.
//
// Whitespace trimming is useful if you don't mind this method returning a path even if
// beforeStringIn is all whitespace and afterStringIn has a whitespace prefix. In that case, the
// result of |charsTakenFromPrefixPtr| will be 0, and it's not suitable for highlighting a match.
- (NSString *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                         suffix:(NSString *)afterStringIn
                               workingDirectory:(NSString *)workingDirectory
                           charsTakenFromPrefix:(int *)charsTakenFromPrefixPtr
                                 trimWhitespace:(BOOL)trimWhitespace;

#pragma mark - Testing

// Tests can subclass and override -fileManager to fake the filesystem. The following methods are
// called: fileExistsAtPathLocally:additionalNetworkPaths:, fileExistsAtPath:, fileExistsAtPath:isDirectory:
@property (nonatomic, readonly) NSFileManager *fileManager;

// Tests can subclass and override these methods to avoid interacting with the filesystem.
- (void)launchTaskWithPath:(NSString *)path arguments:(NSArray *)arguments wait:(BOOL)wait;
- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier path:(NSString *)path;
- (BOOL)openFile:(NSString *)fullPath;
- (BOOL)openURL:(NSURL *)url;
- (BOOL)openURL:(NSURL *)url editorIdentifier:(NSString *)editorIdentifier;
- (BOOL)defaultAppForFileIsEditor:(NSString *)file;
- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)bundleId;
- (NSString *)bundleIdForDefaultAppForFile:(NSString *)file;

@end
