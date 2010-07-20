/*
 * Contains utilities for using Carbon with CGS routines.
 *
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
#include "CGSWindow.h"


CG_EXTERN_C_BEGIN

/* Gets a CGSWindowID for a WindowRef. Implemented in Carbon.framework. 
   This call is deprecated in 10.5. Please use the public alternative, `HIWindowGetCGWindowID`. */
CG_EXTERN CGSWindowID GetNativeWindowFromWindowRef(WindowRef ref) DEPRECATED_IN_MAC_OS_X_VERSION_10_5_AND_LATER;

/* Gets a WindowRef (in the current process) from a CGSWindowID. Implemented in Carbon.framework.
   This call is deprecated in 10.5. Please use the public alternative, `HIWindowFromCGWindowID`. */
CG_EXTERN WindowRef GetWindowRefFromNativeWindow(CGSWindowID wid) DEPRECATED_IN_MAC_OS_X_VERSION_10_5_AND_LATER;

CG_EXTERN_C_END
