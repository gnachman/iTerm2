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

CG_EXTERN_C_BEGIN

/*! Gets whether the display is zoomed. I'm not sure why there's two calls that appear to do the same thing - I think CGSIsZoomed calls through to CGSDisplayIsZoomed. */
CG_EXTERN bool CGSDisplayIsZoomed(void);
CG_EXTERN CGError CGSIsZoomed(CGSConnectionID cid, bool *outIsZoomed);

/*! Gets and sets the cursor scale. The largest the Universal Access prefpane allows you to go is 4.0. */
CG_EXTERN CGError CGSGetCursorScale(CGSConnectionID cid, float *outScale);
CG_EXTERN CGError CGSSetCursorScale(CGSConnectionID cid, float scale);

/*! Gets and sets the state of screen inversion. */
CG_EXTERN bool CGDisplayUsesInvertedPolarity(void);
CG_EXTERN void CGDisplaySetInvertedPolarity(bool invertedPolarity);

/*! Gets and sets whether the screen is grayscale. */
CG_EXTERN bool CGDisplayUsesForceToGray(void);
CG_EXTERN void CGDisplayForceToGray(bool forceToGray);

/*! Sets the display's contrast. There doesn't seem to be a get version of this function. */
CG_EXTERN CGError CGSSetDisplayContrast(float contrast);

CG_EXTERN_C_END
