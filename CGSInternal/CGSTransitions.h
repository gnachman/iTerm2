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

typedef int CGSTransitionID;

typedef enum {
	kCGSTransitionNone,
	kCGSTransitionFade,
	kCGSTransitionZoom,
	kCGSTransitionReveal,
	kCGSTransitionSlide,
	kCGSTransitionWarpFade,
	kCGSTransitionSwap,
	kCGSTransitionCube,
	kCGSTransitionWarpSwitch,
	kCGSTransitionFlip
} CGSTransitionType;

typedef enum {
	/*! Directions for the transition. Some directions don't apply to some transitions. */
	kCGSTransitionDirectionLeft = 1 << 0,
	kCGSTransitionDirectionRight = 1 << 1,
	kCGSTransitionDirectionDown = 1 << 2,
	kCGSTransitionDirectionUp = 1 << 3,
	kCGSTransitionDirectionCenter = 1 << 4,
	
	/*! Reverses a transition. Doesn't apply for all transitions. */
	kCGSTransitionFlagReversed = 1 << 5,
	
	/*! Ignore the background color and only transition the window. */
	kCGSTransitionFlagTransparent = 1 << 7,
} CGSTransitionFlags;

typedef struct {
	int unknown; // always set to zero
	CGSTransitionType type;
	CGSTransitionFlags options;
	CGSWindowID wid; /* 0 means a full screen transition. */
	float *backColor; /* NULL means black. */
} CGSTransitionSpec;

CG_EXTERN_C_BEGIN

/*! Creates a new transition from a `CGSTransitionSpec`. */
CG_EXTERN CGError CGSNewTransition(CGSConnectionID cid, const CGSTransitionSpec *spec, CGSTransitionID *outTransition);

/*! Invokes a transition asynchronously. Note that `duration` is in seconds. */
CG_EXTERN CGError CGSInvokeTransition(CGSConnectionID cid, CGSTransitionID transition, float duration);

/*! Releases a transition. */
CG_EXTERN CGError CGSReleaseTransition(CGSConnectionID cid, CGSTransitionID transition);

CG_EXTERN_C_END
