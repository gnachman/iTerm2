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
#include "CGSInternal.h"

typedef int CGSSessionID;

CG_EXTERN_C_BEGIN

/*! Gets information about the current login session. Keys as of 10.4:
	kCGSSessionGroupIDKey
	kCGSSessionOnConsoleKey
	kCGSSessionIDKey
	kCGSSessionUserNameKey
	kCGSessionLoginDoneKey
	kCGSessionLongUserNameKey
	kCGSSessionSystemSafeBoot
	kCGSSessionLoginwindowSafeLogin
	kCGSSessionConsoleSetKey
	kCGSSessionUserIDKey
 */
CG_EXTERN CFDictionaryRef CGSCopyCurrentSessionDictionary(void);

/*! Creates a new "blank" login session. Switches to the LoginWindow. This does NOT check to see if fast user switching is enabled! */
CG_EXTERN CGError CGSCreateLoginSession(CGSSessionID *outSession);

/*! Releases a session. */
CG_EXTERN CGError CGSReleaseSession(CGSSessionID session);

/*! Gets a list of sessions. Each session dictionary is in the format returned by `CGSCopyCurrentSessionDictionary`. */
CG_EXTERN CFArrayRef CGSCopySessionList(void);

CG_EXTERN_C_END
