/*
 **  iTerm.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: header file for iTerm.app.
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

#ifndef _ITERM_H_
#define _ITERM_H_

#import "AvailabilityMacros.h"
#import <Foundation/Foundation.h>

#define NSLogRect(aRect)    NSLog(@"Rect = %f,%f,%f,%f", (aRect).origin.x, (aRect).origin.y, (aRect).size.width, (aRect).size.height)

#define OSX_TIGERORLATER (floor(NSAppKitVersionNumber) > 743)
#define OSX_LEOPARDORLATER (floor(NSAppKitVersionNumber) > 824)

BOOL IsMavericksOrLater(void);
BOOL IsMountainLionOrLater(void);
BOOL IsLionOrLater(void);
BOOL IsSnowLeopardOrLater(void);
BOOL IsLeopard(void);

#if MAC_OS_X_VERSION_MAX_ALLOWED < 1070
static const int NSWindowCollectionBehaviorFullScreenPrimary = 1 << 7;
static const int NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8;
static const int NSApplicationPresentationAutoHideToolbar = (1 << 11);
static const int NSApplicationPresentationFullScreen = (1 << 10);
static const int NSScrollerStyleLegacy = 0;
#endif

#if MAC_OS_X_VERSION_MAX_ALLOWED < 1060
static const int NSApplicationPresentationAutoHideDock  = (1 <<  0);
static const int NSApplicationPresentationAutoHideMenuBar  = (1 <<  2);
typedef unsigned int NSApplicationPresentationOptions;
static const int NSWindowCollectionBehaviorParticipatesInCycle = 0x20;
static const int NSWindowCollectionBehaviorIgnoresCycle = 0x40;
#endif

#endif // _ITERM_H_
