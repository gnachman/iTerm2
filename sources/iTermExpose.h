// -*- mode:objc -*-
/*
 **  iTermExpose.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements an Exposé-like UI for iTerm2 tabs.
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
#import "FutureMethods.h"

extern const float kItermExposeThumbMargin;

@class iTermExposeView;
@class PTYTab;

@interface iTermExpose : NSObject <NSWindowDelegate>

@property (nonatomic, readonly, getter=isVisible) BOOL visible;

+ (NSString*)labelForTab:(PTYTab*)aTab windowNumber:(int)i tabNumber:(int)j;
+ (void)toggle;
+ (void)exitIfActive;
+ (iTermExpose*)sharedInstance;
- (void)showWindows:(BOOL)fade;
- (NSWindow*)window;
- (void)updateTab:(PTYTab*)theTab;
- (void)computeLayout:(NSMutableArray *)images
               frames:(NSRect*)frames
          screenFrame:(NSRect)screenFrame;
- (void)recomputeIndices:(NSNotification*)notification;

// NSWindowDelegate protocol (informal prior to 10.6)
- (void)windowDidResignKey:(NSNotification *)notification;

- (void)toggleOff;

@end

