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
#include <Carbon/Carbon.h>
#include <ApplicationServices/ApplicationServices.h>

#warning CGSInternal contains PRIVATE FUNCTIONS and should NOT BE USED in shipping applications!

#ifndef MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
	#define AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER UNAVAILABLE_ATTRIBUTE
	#define DEPRECATED_IN_MAC_OS_X_VERSION_10_5_AND_LATER
#endif

#include "CarbonHelpers.h"
#include "CGSAccessibility.h"
#include "CGSCIFilter.h"
#include "CGSConnection.h"
#include "CGSCursor.h"
#include "CGSDebug.h"
#include "CGSDisplays.h"
#include "CGSHotKeys.h"
#include "CGSNotifications.h"
#include "CGSMisc.h"
#include "CGSRegion.h"
#include "CGSSession.h"
#include "CGSTransitions.h"
#include "CGSWindow.h"
#include "CGSWorkspace.h"
