/*
 * Routines for debugging the window server and application drawing.
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
#include "CGSConnection.h"

typedef enum {
	/*! Clears all flags. */
	kCGSDebugOptionNone = 0,
	
	/*! All screen updates are flashed in yellow. Regions under a DisableUpdate are flashed in orange. Regions that are hardware accellerated are painted green. */
	kCGSDebugOptionFlashScreenUpdates = 0x4,
	
	/*! Colors windows green if they are accellerated, otherwise red. Doesn't cause things to refresh properly - leaves excess rects cluttering the screen. */
	kCGSDebugOptionColorByAccelleration = 0x20,
	
	/*! Disables shadows on all windows. */
	kCGSDebugOptionNoShadows = 0x4000,
	
	/*! Setting this disables the pause after a flash when using FlashScreenUpdates or FlashIdenticalUpdates. */
	kCGSDebugOptionNoDelayAfterFlash = 0x20000,
	
	/*! Flushes the contents to the screen after every drawing operation. */
	kCGSDebugOptionAutoflushDrawing = 0x40000,
	
	/*! Highlights mouse tracking areas. Doesn't cause things to refresh correctly - leaves excess rectangles cluttering the screen. */
	kCGSDebugOptionShowMouseTrackingAreas = 0x100000,
	
	/*! Flashes identical updates in red. */
	kCGSDebugOptionFlashIdenticalUpdates = 0x4000000,
	
	/*! Dumps a list of windows to /tmp/WindowServer.winfo.out. This is what Quartz Debug uses to get the window list. */
	kCGSDebugOptionDumpWindowListToFile = 0x80000001,
	
	/*! Dumps a list of connections to /tmp/WindowServer.cinfo.out. */
	kCGSDebugOptionDumpConnectionListToFile = 0x80000002,
	
	/*! Dumps a very verbose debug log of the WindowServer to /tmp/CGLog_WinServer_<PID>. */
	kCGSDebugOptionVerboseLogging = 0x80000006,

	/*! Dumps a very verbose debug log of all processes to /tmp/CGLog_<NAME>_<PID>. */
	kCGSDebugOptionVerboseLoggingAllApps = 0x80000007,
	
	/*! Dumps a list of hotkeys to /tmp/WindowServer.keyinfo.out. */
	kCGSDebugOptionDumpHotKeyListToFile = 0x8000000E,
	
	/*! Dumps information about OpenGL extensions, etc to /tmp/WindowServer.glinfo.out. */
	kCGSDebugOptionDumpOpenGLInfoToFile = 0x80000013,
	
	/*! Dumps a list of shadows to /tmp/WindowServer.shinfo.out. */
	kCGSDebugOptionDumpShadowListToFile = 0x80000014,
	
	/*! Leopard: Dumps information about caches to `/tmp/WindowServer.scinfo.out`. */
	kCGSDebugOptionDumpCacheInformationToFile = 0x80000015,
	
	/*! Leopard: Purges some sort of cache - most likely the same caches dummped with `kCGSDebugOptionDumpCacheInformationToFile`. */
	kCGSDebugOptionPurgeCaches = 0x80000016,
	
	/*! Leopard: Dumps a list of windows to `/tmp/WindowServer.winfo.plist`. This is what Quartz Debug on 10.5 uses to get the window list. */
	kCGSDebugOptionDumpWindowListToPlist = 0x80000017,

	/*! Leopard: DOCUMENTATION PENDING */
	kCGSDebugOptionEnableSurfacePurging = 0x8000001B,

	// Leopard: 0x8000001C - invalid
	
	/*! Leopard: DOCUMENTATION PENDING */
	kCGSDebugOptionDisableSurfacePurging = 0x8000001D,
	
	/*! Leopard: Dumps information about an application's resource usage to `/tmp/CGResources_<NAME>_<PID>`. */
	kCGSDebugOptionDumpResourceUsageToFiles = 0x80000020,
	
	// Leopard: 0x80000022 - something about QuartzGL?
	
	// Leopard: Returns the magic mirror to its normal mode. The magic mirror is what the Dock uses to draw the screen reflection. For more information, see `CGSSetMagicMirror`. */
	kCGSDebugOptionSetMagicMirrorModeNormal = 0x80000023,
	
	/*! Leopard: Disables the magic mirror. It still appears but draws black instead of a reflection. */
	kCGSDebugOptionSetMagicMirrorModeDisabled = 0x80000024,
} CGSDebugOption;


CG_EXTERN_C_BEGIN

/*! Gets and sets the debug options. These options are global and are not reset when your application dies! */
CG_EXTERN CGError CGSGetDebugOptions(int *outCurrentOptions);
CG_EXTERN CGError CGSSetDebugOptions(int options);

/*! Queries the server about its performance. This is how Quartz Debug gets the FPS meter, but not the CPU meter (for that it uses host_processor_info). Quartz Debug subtracts 25 so that it is at zero with the minimum FPS. */
CG_EXTERN CGError CGSGetPerformanceData(CGSConnectionID cid, float *outFPS, float *unk, float *unk2, float *unk3);

CG_EXTERN_C_END
