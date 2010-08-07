/*
 *  GrowlInstallationPrompt-Carbon.h
 *  Growl
 *
 *  Created by Mac-arena the Bored Zo on 2005-05-07.
 *  Copyright 2005 The Growl Project. All rights reserved.
 *
 */

/*!	@header	GrowlInstallationPrompt-Carbon.h
 *	@abstract	Declares the functions used by
 *	 <code>GrowlApplicationBridge</code> to install Growl.
 *	@discussion	These functions are intended for
 *	 <code>GrowlApplicationBridge</code>'s private use only.
 */

/*note (to be moved to GAB-Carbon docs at the earliest opportunity):
 *GAB-Carbon requires Carbon Event Manager. if you are using the classic
 *	Event Manager, GAB-Carbon will not be able to receive an answer to its
 *	confirmation alert, and your application will be blocked.
 *if, for any reason, you cannot use Carbon Event Manager, *DO NOT* attempt to
 *	use the -WithInstaller framework.
 */

#include <Carbon/Carbon.h>

/*!	@function _Growl_ShowInstallationPrompt
 *	@abstract Shows the installation prompt for Growl-WithInstaller.
 */
OSStatus _Growl_ShowInstallationPrompt(void);

/*!	@function showUpdatePromptForVersion:
 *	@abstract Show the update prompt for Growl-WithInstaller
 *
 *	@param updateVersion The version for which an update is available (that is, the version the user will have after updating)
 */
OSStatus _Growl_ShowUpdatePromptForVersion(CFStringRef updateVersion);

