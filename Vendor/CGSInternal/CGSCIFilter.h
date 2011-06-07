/*
 * Copyright (C) 2007-2008 Alacatia Labs
 * 
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 * 
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 * 
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 * 
 * Joe Ranieri joe@alacatia.com
 *
 */

#pragma once
#include "CGSConnection.h"
#include "CGSWindow.h"

typedef int CGSCIFilterID;

/*! Creates a new CGSCIFilter from a filter name. These names are the same as you'd usually use for CIFilters. */
CG_EXTERN CGError CGSNewCIFilterByName(CGSConnectionID cid, CFStringRef filterName, CGSCIFilterID *outFilter);

/*! Adds or removes a CIFilter to a window. Flags are currently unknown (the Dock uses 0x3001).
	Note: This stuff is VERY crashy under 10.4.10 - make sure to remove the filter before minimizing the window or closing it. */
CG_EXTERN CGError CGSAddWindowFilter(CGSConnectionID cid, CGSWindowID wid, CGSCIFilterID filter, int flags);
CG_EXTERN CGError CGSRemoveWindowFilter(CGSConnectionID cid, CGSWindowID wid, CGSCIFilterID filter);

enum {
	kCGWindowFilterUnderlay = 1,
	kCGWindowFilterDock = 0x3001,
};

/*! Loads a set of values into the CIFilter. */
CG_EXTERN CGError CGSSetCIFilterValuesFromDictionary(CGSConnectionID cid, CGSCIFilterID filter, CFDictionaryRef filterValues);

/*! Releases a CIFilter. */
CG_EXTERN CGError CGSReleaseCIFilter(CGSConnectionID cid, CGSCIFilterID filter);

CG_EXTERN_C_END
