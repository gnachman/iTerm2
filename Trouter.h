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

#import <Cocoa/Cocoa.h>

@protocol TrouterDelegate
- (void)trouterLaunchCoprocessWithCommand:(NSString *)command;
@end

@interface Trouter : NSObject {
    NSDictionary *prefs_;
    NSFileManager *fileManager;
	id<TrouterDelegate> delegate_;
}

@property (nonatomic, copy) NSDictionary *prefs;
@property (nonatomic, assign) id<TrouterDelegate> delegate;

- (Trouter*)init;
- (void)dealloc;
- (BOOL)isTextFile:(NSString *)path;
- (BOOL)file:(NSString *)path conformsToUTI:(NSString *)uti;
- (BOOL)isDirectory:(NSString *)path;
- (NSFileManager *)fileManager;
- (NSString *)getFullPath:(NSString *)path
         workingDirectory:(NSString *)workingDirectory
               lineNumber:(NSString **)lineNumber;
- (BOOL)openFileInEditor:(NSString *) path lineNumber:(NSString *)lineNumber;
- (BOOL)canOpenPath:(NSString *)path workingDirectory:(NSString *)workingDirectory;
- (BOOL)openPath:(NSString *)path
    workingDirectory:(NSString *)workingDirectory
    prefix:(NSString *)prefix
    suffix:(NSString *)suffix;

@end
