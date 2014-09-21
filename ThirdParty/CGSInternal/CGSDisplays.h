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
 * Ryan Govostes ryan@alacatia.com
 *
 */

#pragma once

CG_EXTERN_C_BEGIN

/*! Begins a new display configuration transacation. */
CG_EXTERN CGDisplayErr CGSBeginDisplayConfiguration(CGDisplayConfigRef *config);

/*! Sets the origin of a display relative to the main display. The main display is at (0, 0) and contains the menubar. */
CG_EXTERN CGDisplayErr CGSConfigureDisplayOrigin(CGDisplayConfigRef config, CGDirectDisplayID display, int32_t x, int32_t y);

/*! Applies the configuration changes made in this transaction. */
CG_EXTERN CGDisplayErr CGSCompleteDisplayConfiguration(CGDisplayConfigRef config);

/*! Gets the main display. */
CG_EXTERN CGDirectDisplayID CGSMainDisplayID(void);

/*! Drops the configuration changes made in this transaction. */
CG_EXTERN CGDisplayErr CGSCancelDisplayConfiguration(CGDisplayConfigRef config);

/*! Gets a list of on line displays */
CG_EXTERN CGDisplayErr CGSGetOnlineDisplayList(CGDisplayCount maxDisplays, CGDirectDisplayID *displays, CGDisplayCount *outDisplayCount);

/*! Gets a list of active displays */
CG_EXTERN CGDisplayErr CGSGetActiveDisplayList(CGDisplayCount maxDisplays, CGDirectDisplayID *displays, CGDisplayCount *outDisplayCount);

/*! Gets the depth of a display. */
CG_EXTERN CGError CGSGetDisplayDepth(CGDirectDisplayID display, int *outDepth);

/*! Gets the displays at a point. Note that multiple displays can have the same point - think mirroring. */
CG_EXTERN CGError CGSGetDisplaysWithPoint(const CGPoint *point, int maxDisplayCount, CGDirectDisplayID *outDisplays, int *outDisplayCount);

/*! Gets the displays which contain a rect. Note that multiple displays can have the same bounds - think mirroring. */
CG_EXTERN CGError CGSGetDisplaysWithRect(const CGRect *point, int maxDisplayCount, CGDirectDisplayID *outDisplays, int *outDisplayCount);

/*! Gets the bounds for the display. Note that multiple displays can have the same bounds - think mirroring. */
CG_EXTERN CGError CGSGetDisplayRegion(CGDirectDisplayID display, CGSRegionObj *outRegion);
CG_EXTERN CGError CGSGetDisplayBounds(CGDirectDisplayID display, CGRect *outRect);

/*! Gets the number of bytes per row. */
CG_EXTERN CGError CGSGetDisplayRowBytes(CGDirectDisplayID display, int *outRowBytes);

CG_EXTERN_C_END
