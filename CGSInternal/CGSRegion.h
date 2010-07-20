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

#pragma mark types
#if MAC_OS_X_VERSION_10_5 <= MAC_OS_X_VERSION_MAX_ALLOWED
	// on Leopard and up these are CFTypes
	typedef CFTypeRef CGSRegionObj;
	typedef CFTypeRef CGSRegionEnumeratorObj;
#else
	// but opaque types under 10.4
	typedef int CGSRegionObj;
	typedef int CGSRegionEnumeratorObj;
#endif

CG_EXTERN_C_BEGIN

/*! Creates a region from a `CGRect`. */
CG_EXTERN CGError CGSNewRegionWithRect(const CGRect *rect, CGSRegionObj *outRegion);

/*! Creates a region from a list of `CGRect`s. */
CG_EXTERN CGError CGSNewRegionWithRectList(const CGRect *rects, int rectCount, CGSRegionObj *outRegion);

/*! Creates a new region from a QuickDraw region. */
CG_EXTERN CGError CGSNewRegionWithQDRgn(RgnHandle region, CGSRegionObj *outRegion);

/*! Creates an empty region. */
CG_EXTERN CGError CGSNewEmptyRegion(CGSRegionObj *outRegion);

/*! Releases a region. */
CG_EXTERN CGError CGSReleaseRegion(CGSRegionObj region);

/*! Creates a `CGRect` from a region. */
CG_EXTERN CGError CGSGetRegionBounds(CGSRegionObj region, CGRect *outRect);

/*! Determines if two regions are equal. */
CG_EXTERN bool CGSRegionsEqual(CGSRegionObj region1, CGSRegionObj region2);

/* Created a new region by changing the origin an existing one. */
CG_EXTERN CGError CGSOffsetRegion(CGSRegionObj region, float offsetLeft, float offsetTop, CGSRegionObj *outRegion);

/*! Creates a new region by copying an existing one. */
CG_EXTERN CGError CGSCopyRegion(CGSRegionObj region, CGSRegionObj *outRegion);

/*! Creates a new region by combining two regions together. */
CG_EXTERN CGError CGSUnionRegion(CGSRegionObj region1, CGSRegionObj region2, CGSRegionObj *outRegion);

/*! Creates a new region by combining a region and a rect. */
CG_EXTERN CGError CGSUnionRegionWithRect(CGSRegionObj region, CGRect *rect, CGSRegionObj *outRegion);

/*! Creates a region by XORing two regions together. */
CG_EXTERN CGError CGSXorRegion(CGSRegionObj region1, CGSRegionObj region2, CGSRegionObj *outRegion);

/*! Determines if the region is empty. */
CG_EXTERN bool CGSRegionIsEmpty(CGSRegionObj region);

/*! Determines if the region is rectangular. */
CG_EXTERN bool CGSRegionIsRectangular(CGSRegionObj region);

/*! Determines if a point in a region. */
CG_EXTERN bool CGSPointInRegion(CGSRegionObj region, const CGPoint *point);

/*! Determines if a rect is in a region. */
CG_EXTERN bool CGSRectInRegion(CGSRegionObj region, const CGRect *rect);

/*! Determines if a region is inside of a region. */
CG_EXTERN bool CGSRegionInRegion(CGSRegionObj region1, CGSRegionObj region2);

/*! Determines if a rect intersects a region. */
CG_EXTERN bool CGSRegionIntersectsRect(CGSRegionObj obj, const CGRect *rect);

/*! Determines if a region intersects a region. */
CG_EXTERN bool CGSRegionIntersectsRegion(CGSRegionObj region1, CGSRegionObj region2);

/*! Creates a rect from the difference of two regions. */
CG_EXTERN CGError CGSDiffRegion(CGSRegionObj region1, CGSRegionObj region2, CGSRegionObj *outRegion);


#pragma mark region enumerators
/*! Gets the enumerator for a region. */
CG_EXTERN CGSRegionEnumeratorObj CGSRegionEnumerator(CGSRegionObj region);

/*! Releases a region enumerator. */
CG_EXTERN void CGSReleaseRegionEnumerator(CGSRegionEnumeratorObj enumerator);

/*! Gets the next rect of a region. */
CG_EXTERN CGRect* CGSNextRect(CGSRegionEnumeratorObj enumerator);

CG_EXTERN_C_END
