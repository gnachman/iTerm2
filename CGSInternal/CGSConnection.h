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

#include "Compatability.h"

typedef int CGSConnectionID;
static const CGSConnectionID kCGSNullConnectionID = 0;


CG_EXTERN_C_BEGIN

/*! DOCUMENTATION PENDING - verify this is Leopard only! */
CG_EXTERN CGError CGSSetLoginwindowConnection(CGSConnectionID cid) AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER;
CG_EXTERN CGError CGSSetLoginwindowConnectionWithOptions(CGSConnectionID cid, CFDictionaryRef options) AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER;

/*! Enables or disables updates on a connection. The WindowServer will forcibly reenable updates after 1 second. */
CG_EXTERN CGError CGSDisableUpdate(CGSConnectionID cid);
CG_EXTERN CGError CGSReenableUpdate(CGSConnectionID cid);

/*! Is there a menubar associated with this connection? */
CG_EXTERN bool CGSMenuBarExists(CGSConnectionID cid);



#pragma mark notifications
/*! Registers or removes a function to get notified when a connection is created. Only gets notified for connections created in the current application. */
typedef void (*CGSNewConnectionNotificationProc)(CGSConnectionID cid);
CG_EXTERN CGError CGSRegisterForNewConnectionNotification(CGSNewConnectionNotificationProc proc);
CG_EXTERN CGError CGSRemoveNewConnectionNotification(CGSNewConnectionNotificationProc proc);

/*! Registers or removes a function to get notified when a connection is released. Only gets notified for connections created in the current application. */
typedef void (*CGSConnectionDeathNotificationProc)(CGSConnectionID cid);
CG_EXTERN CGError CGSRegisterForConnectionDeathNotification(CGSConnectionDeathNotificationProc proc);
CG_EXTERN CGError CGSRemoveConnectionDeathNotification(CGSConnectionDeathNotificationProc proc);

/*! Creates a new connection to the window server. */
CG_EXTERN CGError CGSNewConnection(int unused, CGSConnectionID *outConnection);

/*! Releases a CGSConnection and all CGSWindows owned by it. */
CG_EXTERN CGError CGSReleaseConnection(CGSConnectionID cid);

/*! Gets the default connection for this process. `CGSMainConnectionID` is just a more modern name. */
CG_EXTERN CGSConnectionID _CGSDefaultConnection(void);
CG_EXTERN CGSConnectionID CGSMainConnectionID(void);

/*! Gets the default connection for the current thread. */
CG_EXTERN CGSConnectionID CGSDefaultConnectionForThread(void);

/* Gets the `pid` that owns this CGSConnection. */ 
CG_EXTERN CGError CGSConnectionGetPID(CGSConnectionID cid, pid_t *outPID);

/*! Gets the CGSConnection for the PSN. */
CG_EXTERN CGError CGSGetConnectionIDForPSN(CGSConnectionID cid, const ProcessSerialNumber *psn, CGSConnectionID *outOwnerCID);

/*! Gets and sets a connection's property. */
CG_EXTERN CGError CGSGetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef *outValue);
CG_EXTERN CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef value);

/*! Closes ALL connections used by the current application. Essentially, it turns it into a console application. */
CG_EXTERN CGError CGSShutdownServerConnections(void);

/*! Only the owner of a window can manipulate it. So, Apple has the concept of a universal owner that owns all windows and can manipulate them all. There can only be one universal owner at a time (the Dock). */
CG_EXTERN CGError CGSSetUniversalOwner(CGSConnectionID cid);

/*! Sets a connection to be a universal owner. This call requires `cid` be a universal connection. */
CG_EXTERN CGError CGSSetOtherUniversalConnection(CGSConnectionID cid, CGSConnectionID otherConnection);

CG_EXTERN_C_END
