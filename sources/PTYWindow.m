/*
 **  PTYWindow.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
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

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermApplication.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermWindowOcclusionChangeMonitor.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "PTYWindow.h"
#import "objc/runtime.h"

NSString *const kTerminalWindowStateRestorationWindowArrangementKey = @"ptyarrangement";
const NSTimeInterval iTermWindowTitleChangeMinimumInterval = 0.1;

@interface NSView (PrivateTitleBarMethods)
- (NSView *)titlebarContainerView;
@end

// Insane hacks inspired by Chrome.
// This makes it possible to implement our own window dragging.
// Absurdly, making the window title invisible does not stop it from being used
// to drag the window.

@interface NSWindow (PrivateAPI)
+ (Class)frameViewClassForStyleMask:(NSUInteger)windowStyle;
@end

@interface NSFrameView : NSView
@end

@interface NSTitledFrame : NSFrameView
// From class-dump
+ (float)_titlebarHeight:(unsigned int)fp8;
@end

@interface NSThemeFrame : NSTitledFrame
@end

@interface NSThemeFrame (Private)
- (CGFloat)_titlebarHeight;
@end

@interface iTermThemeFrame : NSThemeFrame
@end

@implementation iTermThemeFrame

// Height of built-in titlebar to create.
- (CGFloat)_titlebarHeight {
    if ([self.window.ptyWindow.ptyDelegate ptyWindowFullScreen]) {
        if ([[[self class] superclass] instancesRespondToSelector:_cmd]) {
            return [super _titlebarHeight];
        }
    }
    return 1;
}

@end

@implementation NSWindow(iTermWindow)

- (id<PTYWindow>)ptyWindow {
    if ([self conformsToProtocol:@protocol(PTYWindow)]) {
        return (id<PTYWindow>)self;
    } else {
        return nil;
    }
}

@end

#define THE_CLASS iTermWindow
#include "iTermWindowImpl.m"
#undef THE_CLASS

#define THE_CLASS iTermPanel
#include "iTermWindowImpl.m"
#undef THE_CLASS

#define ENABLE_COMPACT_WINDOW_HACK 1
#define THE_CLASS iTermCompactWindow
#include "iTermWindowImpl.m"
#undef THE_CLASS

#define THE_CLASS iTermCompactPanel
#include "iTermWindowImpl.m"
#undef THE_CLASS

// NOTE: If you modify this file update PTYWindow+Scripting.m similarly.
