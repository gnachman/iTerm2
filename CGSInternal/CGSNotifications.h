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
#include "CGSTransitions.h"

typedef enum {
	kCGSNotificationDebugOptionsChanged = 200,
	
	kCGSNotificationMouseMoved = 715,
	
	kCGSNotificationTrackingRegionEntered = 718,
	kCGSNotificationTrackingRegionExited = 719,
	
	// 724 - keyboard preferences changed
	
	// 729, 730 seem to be process deactivated / activated - but only for this process
	// 731 seems to be this process hidden or shown
	
	kCGSNotificationAppUnresponsive = 750,
	kCGSNotificationAppResponsive = 751,
	
	// 761 - hotkey disabled
	// 762 - hotkey enabled (do these two fire twice?)
	
	// 763 - hotkey begins editing
	// 764 - hotkey ends editing
	
	// 765, 766 seem to be about the hotkey state (all disabled, etc)
	
	kCGSNotificationWorkspaceChanged = 1401,
	
	kCGSNotificationTransitionEnded = 1700,
} CGSNotificationType;

//! The data sent with kCGSNotificationAppUnresponsive and kCGSNotificationAppResponsive.
typedef struct {
#if __BIG_ENDIAN__
	uint16_t majorVersion;
	uint16_t minorVersion;
#else
	uint16_t minorVersion;
	uint16_t majorVersion;
#endif
	
	//! The length of the entire notification.
	uint32_t length;	
	
	CGSConnectionID cid;
	pid_t pid;
	ProcessSerialNumber psn;
} CGSProcessNotificationData;

//! The data sent with kCGSNotificationDebugOptionsChanged.
typedef struct {
	int newOptions;
	int unknown[2]; // these two seem to be zero
} CGSDebugNotificationData;

//! The data sent with kCGSNotificationTransitionEnded
typedef struct {
	CGSTransitionID transition;
} CGSTransitionNotificationData;


typedef void (*CGSNotifyProcPtr)(CGSNotificationType type, void *data, unsigned int dataLength, void *userData);

CG_EXTERN_C_BEGIN

//! Registers a function to receive notifications.
CG_EXTERN CGError CGSRegisterNotifyProc(CGSNotifyProcPtr proc, CGSNotificationType type, void *userData);

//! Unregisters a function that was registered to receive notifications.
CG_EXTERN CGError CGSRemoveNotifyProc(CGSNotifyProcPtr proc, CGSNotificationType type, void *userData);

CG_EXTERN_C_END
