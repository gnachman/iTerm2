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

typedef int CGSCursorID;


CG_EXTERN_C_BEGIN

/*! Does the system support hardware cursors? */
CG_EXTERN CGError CGSSystemSupportsHardwareCursor(CGSConnectionID cid, bool *outSupportsHardwareCursor);

/*! Does the system support hardware color cursors? */
CG_EXTERN CGError CGSSystemSupportsColorHardwareCursor(CGSConnectionID cid, bool *outSupportsHardwareCursor);

/*! Shows the cursor. */
CG_EXTERN CGError CGSShowCursor(CGSConnectionID cid);

/*! Hides the cursor. */
CG_EXTERN CGError CGSHideCursor(CGSConnectionID cid);

/*! Hides the cursor until the mouse is moved. */
CG_EXTERN CGError CGSObscureCursor(CGSConnectionID cid);

/*! Gets the cursor location. */
CG_EXTERN CGError CGSGetCurrentCursorLocation(CGSConnectionID cid, CGPoint *outPos);

/*! Gets the name (in reverse DNS form) of a system cursor. */
CG_EXTERN char *CGSCursorNameForSystemCursor(CGSCursorID cursor);

/*! Gets the size of the data for the connection's cursor. */
CG_EXTERN CGError CGSGetCursorDataSize(CGSConnectionID cid, int *outDataSize);

/*! Gets the data for the connection's cursor. */
CG_EXTERN CGError CGSGetCursorData(CGSConnectionID cid, void *outData);

/*! Gets the size of the data for the current cursor. */
CG_EXTERN CGError CGSGetGlobalCursorDataSize(CGSConnectionID cid, int *outDataSize);

/*! Gets the data for the current cursor. */
CG_EXTERN CGError CGSGetGlobalCursorData(CGSConnectionID cid, void *outData, int *outRowBytes, CGRect *outRect, CGRect *outHotSpot, int *outDepth, int *outComponents, int *outBitsPerComponent);

/*! Gets the size of data for a system-defined cursor. */
CG_EXTERN CGError CGSGetSystemDefinedCursorDataSize(CGSConnectionID cid, CGSCursorID cursor, int *outDataSize);

/*! Gets the data for a system-defined cursor. */
CG_EXTERN CGError CGSGetSystemDefinedCursorData(CGSConnectionID cid, CGSCursorID cursor, void *outData, int *outRowBytes, CGRect *outRect, CGRect *outHotSpot, int *outDepth, int *outComponents, int *outBitsPerComponent);

/*! Gets the cursor 'seed'. Every time the cursor is updated, the seed changes. */
CG_EXTERN int CGSCurrentCursorSeed(void);

/*! Shows or hides the spinning beachball of death. */
CG_EXTERN CGError CGSForceWaitCursorActive(CGSConnectionID cid, bool showWaitCursor);

CG_EXTERN_C_END
