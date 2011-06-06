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
#include "CGSTransitions.h"

typedef unsigned int CGSWorkspaceID;

/*! The space id given when we're switching spaces. */
static const CGSWorkspaceID kCGSTransitioningWorkspaceID = 65538;



CG_EXTERN_C_BEGIN

/*! Gets and sets the current workspace. */
CG_EXTERN CGError CGSGetWorkspace(CGSConnectionID cid, CGSWorkspaceID *outWorkspace);
CG_EXTERN CGError CGSSetWorkspace(CGSConnectionID cid, CGSWorkspaceID workspace);

/*! Transitions to a workspace asynchronously. Note that `duration` is in seconds. */
CG_EXTERN CGError CGSSetWorkspaceWithTransition(CGSConnectionID cid, CGSWorkspaceID workspace, CGSTransitionType transition, CGSTransitionFlags options, float duration);

/*! Gets and sets the workspace for a window. */
CG_EXTERN CGError CGSGetWindowWorkspace(CGSConnectionID cid, CGSWindowID wid, CGSWorkspaceID *outWorkspace);
CG_EXTERN CGError CGSSetWindowWorkspace(CGSConnectionID cid, CGSWindowID wid, CGSWorkspaceID workspace);

/*! Gets the number of windows in the workspace. */
CG_EXTERN CGError CGSGetWorkspaceWindowCount(CGSConnectionID cid, int workspaceNumber, int *outCount);
CG_EXTERN CGError CGSGetWorkspaceWindowList(CGSConnectionID cid, int workspaceNumber, int count, CGSWindowID *list, int *outCount);


CG_EXTERN_C_END
