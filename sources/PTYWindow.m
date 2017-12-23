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

#define THE_CLASS iTermWindow
#include "iTermWindowImpl.m"
#undef THE_CLASS

#define THE_CLASS iTermPanel
#include "iTermWindowImpl.m"
#undef THE_CLASS
