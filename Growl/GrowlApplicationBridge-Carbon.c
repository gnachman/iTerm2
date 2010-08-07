//
//  GrowlApplicationBridge-Carbon.c
//  Beep-Carbon
//
//  Created by Mac-arena the Bored Zo on Wed Jun 18 2004.
//  Based on GrowlApplicationBridge.m by Evan Schoenberg.
//  This source code is in the public domain. You may freely link it into any
//    program.
//

#include "GrowlApplicationBridge-Carbon.h"
#include "GrowlInstallationPrompt-Carbon.h"
#include "GrowlDefines.h"
#include "GrowlDefinesInternal.h"
#include "CFGrowlAdditions.h"
#include "GrowlVersionUtilities.h"
#include <unistd.h>

#pragma mark Constants

#define PREFERENCE_PANES_SUBFOLDER_OF_LIBRARY			CFSTR("PreferencePanes")
#define PREFERENCE_PANE_EXTENSION						CFSTR("prefPane")

#define GROWL_PREFPANE_BUNDLE_IDENTIFIER	CFSTR("com.growl.prefpanel")
#define GROWL_PREFPANE_NAME					CFSTR("Growl.prefPane")

#define GROWL_WITHINSTALLER_FRAMEWORK_IDENTIFIER CFSTR("com.growl.growlwithinstallerframework")

#pragma mark -
#pragma mark Private API (declarations)

static CFArrayRef _copyAllPreferencePaneBundles(void);
//this one copies only the first bundle found in the User, Local, Network
//	search-path.
static CFBundleRef _copyGrowlPrefPaneBundle(void);

static Boolean _launchGrowlIfInstalledWithRegistrationDictionary(CFDictionaryRef regDict, GrowlLaunchCallback callback, void *context);

//notification callbacks.
static void _growlIsReady(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void _growlNotificationWasClicked(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void _growlNotificationTimedOut(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

#ifdef GROWL_WITH_INSTALLER
//not static because GIP uses them.
void _userChoseToInstallGrowl(void);
void _userChoseNotToInstallGrowl(void);

static void _checkForPackagedUpdateForGrowlPrefPaneBundle(CFBundleRef growlPrefPaneBundle);
#endif

#pragma mark -
#pragma mark Static variables

static Boolean registeredForClickCallbacks = false;

static const CFOptionFlags bundleIDComparisonFlags = kCFCompareCaseInsensitive | kCFCompareBackwards;

static CFMutableArrayRef targetsToNotifyArray = NULL;

#ifdef GROWL_WITH_INSTALLER
static CFMutableArrayRef queuedGrowlNotifications = NULL;

static Boolean userChoseNotToInstallGrowl = false;
static Boolean promptedToInstallGrowl     = false;
static Boolean promptedToUpgradeGrowl     = false;
#endif

static Boolean registerWhenGrowlIsReady   = false;

static struct Growl_Delegate *delegate = NULL;
static Boolean growlLaunched = false;

#pragma mark -
#pragma mark Pay no attention to that Cocoa behind the curtain

/*NSLog is part of Foundation, and expects an NSString.
 *thanks to toll-free bridging, we can simply declare it like this, and use it
 *	as if it were a pure CF function.
 *
 *we weighed carefully using NSLog, considering the following points:
 *con:
 *	-	NSLog is a Foundation function, and this is advertised as a Carbon API.
 *		(this is a style point.)
 *	-	NSLog expects an NSString as a format, and therefore calls two Obj-C
 *		methods on it (-length and -getCharacters:range:) as of Mac OS X 10.3.5.
 *pro (mainly non-cons):
 *	-	CFLog is private and undocumented (it is not declared in any CF header).
 *	-	fprintf does not work with CoreFoundation objects (no %@), and obtaining
 *		a UTF-8 C string that could be used for %s from a CF string is
 *		convoluted and expensive.
 *	-	rolling our own would invite bugs.
 *	-	NSLog does not autorelease anything.
 *	-	the performance hit of the Objective-C messages is offset by these facts:
 *		-	the hit is minimal.
 *		-	if your app is misbehaving in such a way that we're calling NSLog,
 *			NSLog's performance should not be uppermost in your mind.
 *		-	other methods (such as fprintf, see above) may be even more
 *			expensive.
 *
 *and so you see NSLog declared here.
 */
extern void NSLog(CFStringRef format, ...);

#pragma mark -
#pragma mark Public API

Boolean Growl_SetDelegate(struct Growl_Delegate *newDelegate) {
	if (delegate != newDelegate) {
		if (delegate && (delegate->release))
			delegate->release(delegate);
		if (newDelegate && (newDelegate->retain))
			newDelegate = newDelegate->retain(newDelegate);
		delegate = newDelegate;
	}

	CFStringRef appName = delegate->applicationName;
	if ((!appName) && (delegate->registrationDictionary))
		appName = CFDictionaryGetValue(delegate->registrationDictionary, GROWL_APP_NAME);
	if (!appName) {
		NSLog(CFSTR("%@"), CFSTR("GrowlApplicationBridge: Growl_SetDelegate called, but no application name was found in the delegate"));
		return false;
	}

	CFStringRef growlNotificationClickedName = CFStringCreateWithFormat(
		kCFAllocatorDefault,
		/*formatOptions*/ NULL,
		CFSTR("%@-%d-%@"), appName, getpid(), GROWL_NOTIFICATION_CLICKED);

	CFStringRef growlNotificationTimedOutName = CFStringCreateWithFormat(
		kCFAllocatorDefault,
		/*formatOptions*/ NULL,
		CFSTR("%@-%d-%@"), appName, getpid(), GROWL_NOTIFICATION_TIMED_OUT);

	if (delegate) {
		if (!registeredForClickCallbacks) {
			//register
			CFNotificationCenterRef notificationCenter = CFNotificationCenterGetDistributedCenter();
			CFNotificationCenterAddObserver(notificationCenter, /*observer*/ (void *)_growlNotificationWasClicked, _growlNotificationWasClicked, growlNotificationClickedName, /*object*/ NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			CFNotificationCenterAddObserver(notificationCenter, /*observer*/ (void *)_growlNotificationTimedOut, _growlNotificationTimedOut, growlNotificationTimedOutName, /*object*/ NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
			registeredForClickCallbacks = true;
		}
	} else if (registeredForClickCallbacks) {
		//unregister
		CFNotificationCenterRef notificationCenter = CFNotificationCenterGetDistributedCenter();
		CFNotificationCenterRemoveObserver(notificationCenter, /*observer*/ (void *)_growlNotificationWasClicked, growlNotificationClickedName, /*object*/ NULL);
		CFNotificationCenterRemoveObserver(notificationCenter, /*observer*/ (void *)_growlNotificationTimedOut, growlNotificationTimedOutName, /*object*/ NULL);
		registeredForClickCallbacks = false;
	}

	CFRelease(growlNotificationClickedName);
	CFRelease(growlNotificationTimedOutName);

#ifdef GROWL_WITH_INSTALLER
	Boolean keyExistsAndHasValidFormat_nobodyCares;
	userChoseNotToInstallGrowl = CFPreferencesGetAppBooleanValue(CFSTR("Growl Installation:Do Not Prompt Again"),
																 kCFPreferencesCurrentApplication,
																 &keyExistsAndHasValidFormat_nobodyCares);
#endif

	return (growlLaunched = Growl_RegisterWithDictionary(NULL));
}

struct Growl_Delegate *Growl_GetDelegate(void) {
	return delegate;
}

#pragma mark -

#ifdef GAB_USES_AE
static OSErr AEPutParamString(AppleEvent *event, AEKeyword keyword, CFStringRef stringRef) {
	UInt8 *textBuf;
	CFIndex length, maxBytes, actualBytes;

	length = CFStringGetLength(stringRef); 
	maxBytes = CFStringGetMaximumSizeForEncoding(length,
												 kCFStringEncodingUTF8); 
	textBuf = malloc(maxBytes);
	if (textBuf) {
		CFStringGetBytes(stringRef, CFRangeMake(0, length),
						 kCFStringEncodingUnicode, 0, true,
						 (UInt8 *) textBuf, maxBytes, &actualBytes);

		OSErr err = AEPutParamPtr(event, keyword,
								  typeUnicodeText, textBuf, actualBytes);
		free(textBuf);
		return err;
	} else
		return memFullErr;
}
#endif

void Growl_PostNotificationWithDictionary(CFDictionaryRef userInfo) {
	if (growlLaunched) {
#ifdef GAB_USES_AE
		OSErr err;
		AppleEvent postNotificationEvent;
		AppleEvent replyEvent;
		AEDesc targetGHA;
		OSType ghaSignature = 'GRRR';
		// could use typeApplicationBundleID on 10.3 and later
		err = AECreateDesc(/*typeCode*/ typeApplSignature,
						   /*dataPtr*/ &ghaSignature,
						   /*dataSize*/ sizeof(ghaSignature),
						   /*result*/ &targetGHA);
		if (err != noErr) {
		   NSLog(CFSTR("GrowlApplicationBridge: AECreateDesc returned %li"), (long)err);
		}
		err = AECreateAppleEvent(/*theAEEventClass*/ 'noti',
								 /*theAEEventID*/ 'fygr',
								 /*target*/ &targetGHA,
								 /*returnID*/ kAutoGenerateReturnID,
								 /*transactionID*/ kAnyTransactionID,
								 /*result*/ &postNotificationEvent);
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AECreateAppleEvent returned %li"), (long)err);
		}
		AEDisposeDesc(&targetGHA);
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEDisposeDesc returned %li"), (long)err);
		}

		Boolean sticky;
		int priority;
		CFNumberGetValue(CFDictionaryGetValue(userInfo, GROWL_NOTIFICATION_STICKY), kCFNumberCharType, &sticky);
		CFNumberGetValue(CFDictionaryGetValue(userInfo, GROWL_NOTIFICATION_PRIORITY), kCFNumberIntType, &priority);
		err = AEPutParamString(&postNotificationEvent, 'appl', CFDictionaryGetValue(userInfo, GROWL_APP_NAME));
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEPutParamString(GROWL_APP_NAME) returned %li"), (long)err);
		}
		err = AEPutParamString(&postNotificationEvent, 'desc', CFDictionaryGetValue(userInfo, GROWL_NOTIFICATION_DESCRIPTION));
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEPutParamString(GROWL_NOTIFICATION_DESCRIPTION) returned %li"), (long)err);
		}
		err = AEPutParamString(&postNotificationEvent, 'name', CFDictionaryGetValue(userInfo, GROWL_NOTIFICATION_NAME));
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEPutParamString(GROWL_NOTIFICATION_NAME) returned %li"), (long)err);
		}
		err = AEPutParamString(&postNotificationEvent, 'titl', CFDictionaryGetValue(userInfo, GROWL_NOTIFICATION_TITLE));
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEPutParamString(GROWL_NOTIFICATION_TITLE) returned %li"), (long)err);
		}
		err = AEPutParamPtr(&postNotificationEvent, 'prio', typeSInt32, &priority, sizeof(priority));
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEPutParamPtr(GROWL_NOTIFICATION_PRIORITY) returned %li"), (long)err);
		}
		err = AEPutParamPtr(&postNotificationEvent, 'stck', sticky ? typeTrue : typeFalse, &sticky, sizeof(sticky));
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AEPutParamPtr(GROWL_NOTIFICATION_STICKY) returned %li"), (long)err);
		}
		err = AESendMessage(/*event*/ &postNotificationEvent,
							/*reply*/ &replyEvent,
							/*sendMode*/ kAENoReply,
							/*timeOutInTicks*/ kAEDefaultTimeout);
		if (err != noErr) {
			NSLog(CFSTR("GrowlApplicationBridge: AESendMessage returned %li"), (long)err);
		}
#else
		CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
		                                     GROWL_NOTIFICATION,
		                                     /*object*/ NULL,
		                                     userInfo,
		                                     /*deliverImmediately*/ false);
#endif
#ifdef GROWL_WITH_INSTALLER
	} else {
		/*if Growl launches, and the user hasn't already said NO to installing
		 *	it, store this notification for posting
		 */
		if (!userChoseNotToInstallGrowl) {
			//in case the dictionary is mutable, make a copy.
			userInfo = CFDictionaryCreateCopy(CFGetAllocator(userInfo), userInfo);

			if (!queuedGrowlNotifications)
				queuedGrowlNotifications = CFArrayCreateMutable(kCFAllocatorDefault, /*capacity*/ 0, &kCFTypeArrayCallBacks);
			CFArrayAppendValue(queuedGrowlNotifications, userInfo);

			//if we have not already asked the user to install Growl, do it now
			if (!promptedToInstallGrowl) {
				OSStatus err = _Growl_ShowInstallationPrompt();
				promptedToInstallGrowl = (err == noErr);
				//_Growl_ShowInstallationPrompt prints its own errors.
			}

			CFRelease(userInfo);
		}
#endif GROWL_WITH_INSTALLER
	}
}

void Growl_PostNotification(const struct Growl_Notification *notification) {
	if (!notification) {
		NSLog(CFSTR("%@"), CFSTR("GrowlApplicationBridge: Growl_PostNotification called with a NULL notification"));
		return;
	}
	if (!delegate) {
		NSLog(CFSTR("%@"), CFSTR("GrowlApplicationBridge: Growl_PostNotification called, but no delegate is in effect to supply an application name - either set a delegate, or use Growl_PostNotificationWithDictionary instead"));
		return;
	}
	CFStringRef appName = delegate->applicationName;
	if ((!appName) && (delegate->registrationDictionary))
		appName = CFDictionaryGetValue(delegate->registrationDictionary, GROWL_APP_NAME);
	if (!appName) {
		NSLog(CFSTR("%@"), CFSTR("GrowlApplicationBridge: Growl_PostNotification called, but no application name was found in the delegate"));
		return;
	}

	enum {
		appNameIndex,
		appPidIndex,
		nameIndex,
		titleIndex, descriptionIndex,
		priorityIndex,
		stickyIndex,
		iconIndex,
		appIconIndex,
		clickContextIndex,

		highestKeyIndex = 9,
		numKeys
	};
	const void *keys[numKeys] = {
		GROWL_APP_NAME,
		GROWL_APP_PID,
		GROWL_NOTIFICATION_NAME,
		GROWL_NOTIFICATION_TITLE, GROWL_NOTIFICATION_DESCRIPTION,
		GROWL_NOTIFICATION_PRIORITY,
		GROWL_NOTIFICATION_STICKY,
		GROWL_NOTIFICATION_ICON,
		GROWL_NOTIFICATION_APP_ICON,
		GROWL_NOTIFICATION_CLICK_CONTEXT,
	};
	int pid = getpid();
	CFNumberRef pidNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
	CFNumberRef priorityNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(notification->priority));
	Boolean isSticky = notification->isSticky;
	CFNumberRef stickyNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberCharType, &isSticky);

	const void *values[numKeys] = {
		appName, //0
		pidNumber, //1
		notification->name, //2
		notification->title, notification->description, //3, 4
		priorityNumber, //5
		stickyNumber, //6
		notification->iconData, //7
		NULL, //8
		NULL, //9
	};

	//make sure we have both a name and a title
	if (values[titleIndex] && !values[nameIndex])
		values[nameIndex] = values[titleIndex];
	else if (values[nameIndex] && !values[titleIndex])
		values[titleIndex] = values[nameIndex];

	//... and a description
	if (!values[descriptionIndex])
		values[descriptionIndex] = CFSTR("");

	//now, target the first NULL value.
	//if there was iconData, this is index 8; else, it is index 7.
	unsigned pairIndex = iconIndex + (values[iconIndex] != NULL);

	//...and set the custom application icon there.
	if (delegate->applicationIconData) {
		keys[pairIndex] = GROWL_NOTIFICATION_APP_ICON;
		values[pairIndex] = delegate->applicationIconData;
		++pairIndex;
	}

	if (notification->clickContext) {
		keys[pairIndex] = GROWL_NOTIFICATION_CLICK_CONTEXT;
		values[pairIndex] = notification->clickContext;
		++pairIndex;
	}

	CFDictionaryRef userInfo = CFDictionaryCreate(kCFAllocatorDefault,
	                                              keys, values,
	                                              /*numValues*/ pairIndex,
	                                              &kCFTypeDictionaryKeyCallBacks,
	                                              &kCFTypeDictionaryValueCallBacks);

	Growl_PostNotificationWithDictionary(userInfo);

	CFRelease(userInfo);
	CFRelease(pidNumber);
	CFRelease(priorityNumber);
	CFRelease(stickyNumber);
}

void Growl_NotifyWithTitleDescriptionNameIconPriorityStickyClickContext(
	CFStringRef title,
	CFStringRef description,
	CFStringRef notificationName,
	CFDataRef iconData,
	signed int priority,
	Boolean isSticky,
	CFPropertyListRef clickContext)
{
	struct Growl_Notification notification;
	InitGrowlNotification(&notification);

	notification.name = notificationName;
	notification.title = title;
	notification.description = description;
	notification.iconData = iconData;
	notification.priority = priority;
	notification.isSticky = (isSticky != false);
	notification.clickContext = clickContext;

	Growl_PostNotification(&notification);
}

#pragma mark -

Boolean Growl_RegisterWithDictionary(CFDictionaryRef regDict) {
	if (regDict) regDict = Growl_CreateRegistrationDictionaryByFillingInDictionary(regDict);
	else         regDict = Growl_CreateBestRegistrationDictionary();

	Boolean success = _launchGrowlIfInstalledWithRegistrationDictionary(regDict, /*callback*/ NULL, /*context*/ NULL);

	CFRelease(regDict);

	return success;
}

void Growl_Reregister(void) {
	Growl_RegisterWithDictionary(NULL);
}

#pragma mark -

void Growl_SetWillRegisterWhenGrowlIsReady(Boolean flag) {
	registerWhenGrowlIsReady = flag;
}
Boolean Growl_WillRegisterWhenGrowlIsReady(void) {
	return registerWhenGrowlIsReady;
}

#pragma mark -

CFDictionaryRef Growl_CopyRegistrationDictionaryFromDelegate(void) {
	CFDictionaryRef regDict = NULL;
	if (delegate) {
		/*create the registration dictionary.
		 *this is the same as the one in the delegate or the main bundle, but
		 *	it must have GROWL_APP_NAME in it.
		 */
		regDict = delegate->registrationDictionary;
		if (regDict)
			regDict = CFDictionaryCreateCopy(kCFAllocatorDefault, regDict);
	}
	return regDict;
}

CFDictionaryRef Growl_CopyRegistrationDictionaryFromBundle(CFBundleRef bundle) {
	if (!bundle) bundle = CFBundleGetMainBundle();

	CFDictionaryRef regDict = NULL;
	CFURLRef regDictURL = CFBundleCopyResourceURL(bundle, CFSTR("Growl Registration Ticket"), GROWL_REG_DICT_EXTENSION, /*subDirName*/ NULL);
	CFStringRef regDictPath = NULL;
	if (!regDictURL) {
		/*get the location of the bundle, so we can log that it doesn't
		 *	have an auto-discoverable plist.
		 */
		CFURLRef bundleURL = CFBundleCopyBundleURL(bundle);
		if (bundleURL) {
			CFStringRef bundlePath = CFURLCopyFileSystemPath(bundleURL, kCFURLPOSIXPathStyle);
			if (!bundlePath) bundlePath = CFRetain(bundleURL);
			CFRelease(bundleURL);
			if (bundlePath) {
				NSLog(CFSTR("GrowlApplicationBridge: Delegate did not supply a registration dictionary, and the app bundle at %@ does not have one"), bundlePath);
				CFRelease(bundlePath);
			}
		}
	} else {
		//get the path, for error messages.
		regDictPath = CFURLCopyFileSystemPath(regDictURL, kCFURLPOSIXPathStyle);
		if (!regDictPath) regDictPath = CFRetain(regDictURL);

		//read the plist.
		CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, regDictURL);
		if (stream) {
			CFReadStreamOpen(stream);

			CFPropertyListFormat format_noOneCares;
			CFStringRef errorString = NULL;
			regDict = CFPropertyListCreateFromStream(kCFAllocatorDefault,
													 stream,
									/*streamLength*/ 0, //read to EOF
													 kCFPropertyListImmutable,
													 &format_noOneCares,
													 &errorString);

			CFReadStreamClose(stream);
			CFRelease(stream);
			if (errorString) {
				NSLog(CFSTR("GrowlApplicationBridge: Got error reading property list at %@: %@"), regDictPath, errorString);
				CFRelease(errorString);
			}
		}

		if (!regDict) {
			NSLog(CFSTR("GrowlApplicationBridge: Delegate did not supply a registration dictionary, and it could not be loaded from %@"), regDictPath);
		} else {
			if (CFGetTypeID(regDict) != CFDictionaryGetTypeID()) {
				//this isn't a dictionary. reject it.
				CFStringRef dictionaryTypeDescription = CFCopyTypeIDDescription(CFDictionaryGetTypeID());
				CFStringRef actualTypeDescription = CFCopyTypeIDDescription(CFGetTypeID(regDict));

				NSLog(CFSTR("GrowlApplicationBridge: Registration dictionary file at %@ didn't contain a dictionary (dictionary type ID is '%@' whereas the file contained '%@'); description of object follows\n%@"), regDictPath, dictionaryTypeDescription, actualTypeDescription, regDict);

				CFRelease(actualTypeDescription);
				CFRelease(dictionaryTypeDescription);

				CFRelease(regDict);
				regDict = NULL;
			}
		}
		CFRelease(regDictPath);
		CFRelease(regDictURL);
	}
	return regDict;
}

CFDictionaryRef Growl_CreateBestRegistrationDictionary(void) {
	CFDictionaryRef regDict = Growl_CopyRegistrationDictionaryFromDelegate();
	if (!regDict) regDict = Growl_CopyRegistrationDictionaryFromBundle(NULL);
	if (regDict) {
		CFDictionaryRef filledIn = Growl_CreateRegistrationDictionaryByFillingInDictionary(regDict);
		CFRelease(regDict);
		regDict = filledIn;
	}
	return regDict;
}

#pragma mark -

CFDictionaryRef Growl_CreateRegistrationDictionaryByFillingInDictionary(CFDictionaryRef regDict) {
	return Growl_CreateRegistrationDictionaryByFillingInDictionaryRestrictedToKeys(regDict, /*keys*/ NULL);
}

CFDictionaryRef Growl_CreateRegistrationDictionaryByFillingInDictionaryRestrictedToKeys(CFDictionaryRef regDict, CFSetRef keys) {
	if (!regDict) return NULL;

	CFMutableDictionaryRef mRegDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, /*capacity*/ 0, regDict);

	if ((!keys) || CFSetContainsValue(keys, GROWL_APP_NAME)) {
		if (!CFDictionaryContainsKey(mRegDict, GROWL_APP_NAME)) {
			CFStringRef appName = NULL;
			if (delegate) {
				appName = delegate->applicationName;
				if ((!appName) && delegate && (delegate->registrationDictionary))
					appName = CFDictionaryGetValue(delegate->registrationDictionary, GROWL_APP_NAME);
				if (appName)
					appName = CFRetain(appName);
			}
			if (!appName)
				appName = copyCurrentProcessName();

			if (appName) {
				CFDictionarySetValue(mRegDict, GROWL_APP_NAME, appName);
				CFRelease(appName);
			}
		}
	}

	if ((!keys) || CFSetContainsValue(keys, GROWL_APP_ICON)) {
		if (!CFDictionaryContainsKey(mRegDict, GROWL_APP_ICON)) {
			CFDataRef appIconData = NULL;
			if (delegate) {
				appIconData = delegate->applicationIconData;
				if ((!appIconData) && (delegate->registrationDictionary))
					appIconData = CFDictionaryGetValue(delegate->registrationDictionary, GROWL_APP_ICON);
				if (appIconData)
					appIconData = CFRetain(appIconData);
			}
			if (!appIconData) {
				CFURLRef myURL = copyCurrentProcessURL();
				if (myURL) {
					appIconData = copyIconDataForURL(myURL);
					CFRelease(myURL);
				}
			}

			if (appIconData) {
				CFDictionarySetValue(mRegDict, GROWL_APP_ICON, appIconData);
				CFRelease(appIconData);
			}
		}
	}

	if ((!keys) || CFSetContainsValue(keys, GROWL_APP_LOCATION)) {
		if (!CFDictionaryContainsKey(mRegDict, GROWL_APP_LOCATION)) {
			CFURLRef myURL = copyCurrentProcessURL();
			if (myURL) {
				CFDictionaryRef file_data = createDockDescriptionForURL(myURL);
				if (file_data) {
					enum { numPairs = 1 };
					const void *locationKeys[numPairs]   = { CFSTR("file-data") };
					const void *locationValues[numPairs] = { file_data };

					CFDictionaryRef location = CFDictionaryCreate(kCFAllocatorDefault, locationKeys, locationValues, numPairs, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

					if (location) {
						CFDictionarySetValue(mRegDict, GROWL_APP_LOCATION, location);
						CFRelease(location);
					}
				} else {
					CFDictionaryRemoveValue(mRegDict, GROWL_APP_LOCATION);
				}
				CFRelease(myURL);
			}
		}
	}

	if ((!keys) || CFSetContainsValue(keys, GROWL_NOTIFICATIONS_DEFAULT)) {
		if (!CFDictionaryContainsKey(mRegDict, GROWL_NOTIFICATIONS_DEFAULT)) {
			CFArrayRef all = CFDictionaryGetValue(mRegDict, GROWL_NOTIFICATIONS_ALL);
			if (all)
				CFDictionarySetValue(mRegDict, GROWL_NOTIFICATIONS_DEFAULT, all);
		}
	}

	CFDictionaryRef result = CFDictionaryCreateCopy(kCFAllocatorDefault, mRegDict);
	CFRelease(mRegDict);
	return result;
}

#pragma mark -

/*Growl_IsInstalled
 *
 *Determines whether the Growl prefpane and its helper app are installed.
 *Returns true if Growl is installed, false otherwise.
 */
Boolean Growl_IsInstalled(void) {
	return _copyGrowlPrefPaneBundle() != NULL;
}

/*Growl_IsRunning
 *
 *Cycles through the process list to find whether GrowlHelperApp is running.
 *Returns true if Growl is running, false otherwise.
 */
Boolean Growl_IsRunning(void) {
	Boolean growlIsRunning = false;
	ProcessSerialNumber PSN = { 0, kNoProcess };

	while (GetNextProcess(&PSN) == noErr) {
		CFDictionaryRef infoDict = ProcessInformationCopyDictionary(&PSN, kProcessDictionaryIncludeAllInformationMask);

		if (CFEqual(CFDictionaryGetValue(infoDict, kCFBundleIdentifierKey), CFSTR("com.Growl.GrowlHelperApp"))) {
			growlIsRunning = true;
			CFRelease(infoDict);
			break;
		}
		CFRelease(infoDict);
	}

	return growlIsRunning;
}

#pragma mark -

Boolean Growl_LaunchIfInstalled(GrowlLaunchCallback callback, void *context) {
	CFDictionaryRef regDict = Growl_CreateBestRegistrationDictionary();
	Boolean success = _launchGrowlIfInstalledWithRegistrationDictionary(regDict, callback, context);
	if (regDict) CFRelease(regDict);
	return success;
}

#pragma mark -
#pragma mark Private API

static Boolean _launchGrowlIfInstalledWithRegistrationDictionary(CFDictionaryRef regDict, GrowlLaunchCallback callback, void *context) {
	CFArrayRef		prefPanes;
	CFIndex			prefPaneIndex = 0, numPrefPanes = 0;
	CFStringRef		bundleIdentifier;
	CFBundleRef		prefPaneBundle;
	CFBundleRef		growlPrefPaneBundle = NULL;
	Boolean			success = false;

	/*Enumerate all installed preference panes, looking for the Growl prefpane
	 *	bundle identifier and stopping when we find it.
	 *Note that we check the bundle identifier because we should not insist
	 *	that the user not rename his preference pane files, although most users
	 *	of course will not.  If the user wants to mutilate the Info.plist file
	 *	inside the bundle, he/she deserves to not have a working Growl
	 *	installation.
	 */
	prefPanes = _copyAllPreferencePaneBundles();
	if (prefPanes) {
		numPrefPanes = CFArrayGetCount(prefPanes);

		while (prefPaneIndex < numPrefPanes) {
			prefPaneBundle = (CFBundleRef)CFArrayGetValueAtIndex(prefPanes, prefPaneIndex++);

			if (prefPaneBundle) {
				bundleIdentifier = CFBundleGetIdentifier(prefPaneBundle);

				if (bundleIdentifier && (CFStringCompare(bundleIdentifier, GROWL_PREFPANE_BUNDLE_IDENTIFIER, kCFCompareCaseInsensitive | kCFCompareBackwards) == kCFCompareEqualTo)) {
					growlPrefPaneBundle = (CFBundleRef)CFRetain(prefPaneBundle);
					break;
				}
			}
		}

		CFRelease(prefPanes);
	}

	if (growlPrefPaneBundle) {
#ifdef GROWL_WITH_INSTALLER
		_checkForPackagedUpdateForGrowlPrefPaneBundle(growlPrefPaneBundle);
#endif

		CFURLRef	growlHelperAppURL = NULL;

		//Extract the path to the Growl helper app from the prefpane's bundle
		growlHelperAppURL = CFBundleCopyResourceURL(growlPrefPaneBundle, CFSTR("GrowlHelperApp"), CFSTR("app"), /*subDirName*/ NULL);

		if (growlHelperAppURL) {
			if (callback || (delegate && delegate->growlIsReady)) {
				//the Growl helper app will notify us via growlIsReady when it is done launching
				CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), /*observer*/ (void *)_growlIsReady, _growlIsReady, GROWL_IS_READY, /*object*/ NULL, CFNotificationSuspensionBehaviorCoalesce);

				if (callback) {
					//We probably will never have more than one callback/context set at a time, but this is cleaner than the alternatives
					if (!targetsToNotifyArray)
						targetsToNotifyArray = CFArrayCreateMutable(kCFAllocatorDefault, /*capacity*/ 0, &kCFTypeArrayCallBacks);

					CFStringRef keys[] = { CFSTR("Callback"), CFSTR("Context") };
					void *values[] = { (void *)callback, context };
					CFDictionaryRef	infoDict = CFDictionaryCreate(kCFAllocatorDefault,
																  (const void **)keys,
																  (const void **)values,
																  /*numValues*/ 2,
																  &kCFTypeDictionaryKeyCallBacks,
																  /*valueCallbacks*/ NULL);
					if (infoDict) {
						CFArrayAppendValue(targetsToNotifyArray, infoDict);
						CFRelease(infoDict);
					}
				}
			}

			CFArrayRef itemsToOpen = NULL;

			if (regDict) {
				/*since we have a registration dictionary, we must want to
				 *	register.
				 *if this block gets skipped, GHA will simply be launched
				 *	directly (as if the user had double-clicked on it or
				 *	clicked 'Start Growl').
				 */
				//(1) create the path: /tmp/$UID/TemporaryItems/$UUID.growlRegDict
				CFStringRef tmp = copyTemporaryFolderPath();
				if (!tmp) {
					NSLog(CFSTR("%@"), CFSTR("GrowlApplicationBridge: Could not find the temporary directory path, therefore cannot register."));
				} else {
					CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
					CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
					CFRelease(uuid);
					CFStringRef extension = GROWL_REG_DICT_EXTENSION;
					CFStringRef slash = CFSTR("/");
					CFStringRef fullstop = CFSTR(".");

					enum { numComponents = 5 };
					const void *componentObjects[numComponents] = {
						tmp, slash, uuidString, fullstop, extension,
					};
					CFArrayRef components = CFArrayCreate(kCFAllocatorDefault, componentObjects, numComponents, &kCFTypeArrayCallBacks);
					CFRelease(uuidString);
					CFStringRef regDictPath = CFStringCreateByCombiningStrings(kCFAllocatorDefault, components, /*separator*/ CFSTR(""));
					CFRelease(components);

					CFURLRef regDictURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, regDictPath, kCFURLPOSIXPathStyle, /*isDirectory*/ false);
					CFRelease(regDictPath);

					//(2) write out the dictionary to that path.
					CFWriteStreamRef stream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, regDictURL);
					CFWriteStreamOpen(stream);

					CFStringRef errorString = NULL;
					CFPropertyListWriteToStream(regDict, stream, kCFPropertyListBinaryFormat_v1_0, &errorString);
					if (errorString) {
						NSLog(CFSTR("GrowlApplicationBridge: Error writing registration dictionary to URL %@: %@"), regDictURL, errorString);
						NSLog(CFSTR("GrowlApplicationBridge: Registration dictionary follows\n%@"), regDict);
					}

					CFWriteStreamClose(stream);
					CFRelease(stream);

					//(3) be sure to open the file if it exists.
					if (!errorString) {
						itemsToOpen = CFArrayCreate(kCFAllocatorDefault, (const void **)&regDictURL, /*count*/ 1, &kCFTypeArrayCallBacks);
					}
					CFRelease(regDictURL);
				} //if (tmp)
			} //if (regDict)

			//Houston, we are go for launch.
			//we use LSOpenFromURLSpec because it can suppress adding to recents.
			struct LSLaunchURLSpec launchSpec = {
				.appURL = growlHelperAppURL,
				.itemURLs = itemsToOpen,
				.passThruParams = NULL,
				.launchFlags = kLSLaunchDontAddToRecents | kLSLaunchDontSwitch | kLSLaunchNoParams | kLSLaunchAsync,
				.asyncRefCon = NULL,
			};
			success = (LSOpenFromURLSpec(&launchSpec, /*outLaunchedURL*/ NULL) == noErr);
			CFRelease(growlHelperAppURL);
			if (itemsToOpen) CFRelease(itemsToOpen);
		} //if (growlHelperAppURL)

		CFRelease(growlPrefPaneBundle);
	} //if (growlPrefPaneBundle)

	return success;
}

//Returns an array of paths to all user-installed .prefPane bundles
static CFArrayRef _copyAllPreferencePaneBundles(void) {
	CFStringRef			prefPaneExtension = PREFERENCE_PANE_EXTENSION;
	CFMutableArrayRef	allPreferencePaneBundles = CFArrayCreateMutable(kCFAllocatorDefault, /*capacity*/ 0, &kCFTypeArrayCallBacks);
	CFArrayRef			curDirContents;
	CFRange				contentsRange = { 0, 0 };
	CFURLRef			curDirURL;
	OSStatus			err;
	FSRef				curDir;

	//Find Library directories in all domains except /System (as of Panther, that's ~/Library, /Library, and /Network/Library)
#define PREFPANEGRAB(destArray, domain) \
	err = FSFindFolder((domain), kPreferencePanesFolderType, /*createFolder*/ false, &curDir); \
	if (err == noErr) { \
		curDirURL = CFURLCreateFromFSRef(kCFAllocatorDefault, &curDir); \
		if (curDirURL) { \
			curDirContents = CFBundleCreateBundlesFromDirectory(kCFAllocatorDefault, curDirURL, prefPaneExtension); \
			if (curDirContents) { \
				contentsRange.length = CFArrayGetCount(curDirContents); \
				CFArrayAppendArray((destArray), curDirContents, contentsRange); \
				CFRelease(curDirContents); \
			} \
			CFRelease(curDirURL); \
		} \
	}

	PREFPANEGRAB(allPreferencePaneBundles, kUserDomain)
	PREFPANEGRAB(allPreferencePaneBundles, kLocalDomain)
	PREFPANEGRAB(allPreferencePaneBundles, kNetworkDomain)

#undef PREFPANEGRAB

	return allPreferencePaneBundles;
}

static CFBundleRef _copyGrowlPrefPaneBundle(void) {
	CFBundleRef		growlPrefPaneBundle = NULL;

	CFStringRef		bundleIdentifier;
	CFBundleRef		prefPaneBundle = NULL;

	//first try looking up the prefpane by name.
	{
//outPtr should be a CFBundleRef *.
#define COPYPREFPANE(domain, outPtr) \
	do { \
		FSRef domainRef; \
		OSStatus err = FSFindFolder((domain), kPreferencePanesFolderType, /*createFolder*/ false, &domainRef); \
		if (err == noErr) { \
			CFURLRef domainURL = CFURLCreateFromFSRef(kCFAllocatorDefault, &domainRef); \
			if (domainURL) { \
				CFURLRef prefPaneURL = CFURLCreateCopyAppendingPathComponent(kCFAllocatorDefault, domainURL, GROWL_PREFPANE_NAME, /*isDirectory*/ true); \
				CFRelease(domainURL); \
				if (prefPaneURL) { \
					(*outPtr) = CFBundleCreate(kCFAllocatorDefault, prefPaneURL); \
					CFRelease(prefPaneURL); \
				} \
			} \
		} \
	} while (0)

		//User domain.
		COPYPREFPANE(kUserDomain, &prefPaneBundle);
		if (prefPaneBundle) {
			bundleIdentifier = CFBundleGetIdentifier(prefPaneBundle);

			if (bundleIdentifier && (CFStringCompare(bundleIdentifier, GROWL_PREFPANE_BUNDLE_IDENTIFIER, bundleIDComparisonFlags) == kCFCompareEqualTo)) {
				growlPrefPaneBundle = prefPaneBundle;
			}
		}

		if (!growlPrefPaneBundle) {
			//Local domain.
			COPYPREFPANE(kLocalDomain, &prefPaneBundle);
			if (prefPaneBundle) {
				bundleIdentifier = CFBundleGetIdentifier(prefPaneBundle);

				if (bundleIdentifier && (CFStringCompare(bundleIdentifier, GROWL_PREFPANE_BUNDLE_IDENTIFIER, bundleIDComparisonFlags) == kCFCompareEqualTo)) {
					growlPrefPaneBundle = prefPaneBundle;
				}
			}

			if (!growlPrefPaneBundle) {
				//Network domain.
				COPYPREFPANE(kNetworkDomain, &prefPaneBundle);
				if (prefPaneBundle) {
					bundleIdentifier = CFBundleGetIdentifier(prefPaneBundle);

					if (bundleIdentifier && (CFStringCompare(bundleIdentifier, GROWL_PREFPANE_BUNDLE_IDENTIFIER, bundleIDComparisonFlags) == kCFCompareEqualTo)) {
						growlPrefPaneBundle = prefPaneBundle;
					}
				}
			}
		}

#undef COPYPREFPANE
	}

	if (!growlPrefPaneBundle) {
		//Enumerate all installed preference panes, looking for the growl prefpane bundle identifier and stopping when we find it
		//Note that we check the bundle identifier because we should not insist the user not rename his preference pane files, although most users
		//of course will not.  If the user wants to destroy the info.plist file inside the bundle, he/she deserves not to have a working Growl installation.
		CFArrayRef		prefPanes = _copyAllPreferencePaneBundles();
		if (prefPanes) {
			CFIndex		prefPaneIndex = 0, numPrefPanes = CFArrayGetCount(prefPanes);

			while (prefPaneIndex < numPrefPanes) {
				prefPaneBundle = (CFBundleRef)CFArrayGetValueAtIndex(prefPanes, prefPaneIndex++);

				if (prefPaneBundle){
					bundleIdentifier = CFBundleGetIdentifier(prefPaneBundle);

					if (bundleIdentifier && (CFStringCompare(bundleIdentifier, GROWL_PREFPANE_BUNDLE_IDENTIFIER, bundleIDComparisonFlags) == kCFCompareEqualTo)) {
						growlPrefPaneBundle = (CFBundleRef)CFRetain(prefPaneBundle);
						break;
					}
				}
			}

			CFRelease(prefPanes);
		}
	}

	return growlPrefPaneBundle;
}

#ifdef GROWL_WITH_INSTALLER
void _userChoseToInstallGrowl(void) {
	//the Growl helper app will notify us via growlIsReady after the user launches it
	CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), /*observer*/ (void *)_growlIsReady, _growlIsReady, GROWL_IS_READY, /*object*/ NULL, CFNotificationSuspensionBehaviorCoalesce);
}
void _userChoseNotToInstallGrowl(void) {
	//Note the user's action so we stop queueing notifications, etc.
	userChoseNotToInstallGrowl = true;
	
	//Clear our queued notifications; we won't be needing them
	if (queuedGrowlNotifications) {
		CFRelease(queuedGrowlNotifications);
		queuedGrowlNotifications = NULL;
	}
}

static void _checkForPackagedUpdateForGrowlPrefPaneBundle(CFBundleRef growlPrefPaneBundle) {
	if (!growlPrefPaneBundle)
		NSLog(CFSTR("GrowlApplicationBridge: can't check for an update for a NULL prefPane"));
	else {
		CFBundleRef frameworkBundle = CFBundleGetBundleWithIdentifier(GROWL_WITHINSTALLER_FRAMEWORK_IDENTIFIER);

		if (!frameworkBundle)
			NSLog(CFSTR("GrowlApplicationBridge: could not locate framework bundle (forget about installing Growl); had looked for bundle with identifier '%@'"), GROWL_WITHINSTALLER_FRAMEWORK_IDENTIFIER);
		else {
			CFURLRef ourInfoDictURL = CFBundleCopyResourceURL(frameworkBundle,
															  CFSTR("GrowlPrefPaneInfo"),
															  CFSTR("plist"),
															  /*subDirName*/ NULL);
			if (!ourInfoDictURL)
				NSLog(CFSTR("GrowlApplicationBridge: could not find '%@.%@' in framework bundle %@"), CFSTR("GrowlPrefPaneInfo"), CFSTR("plist"), frameworkBundle);
			else {
				CFPropertyListFormat format_nobodyCares;
				CFStringRef errorString = NULL;
				CFDictionaryRef ourInfoDict = createPropertyListFromURL(ourInfoDictURL, kCFPropertyListImmutable, &format_nobodyCares, &errorString);
				if (!ourInfoDict)
					NSLog(CFSTR("GrowlApplicationBridge: could not create property list from data at %@ (which should be inside the framework bundle)"), CFSTR("GrowlPrefPaneInfo"), ourInfoDictURL);
				else {
					CFStringRef ourVersion = CFDictionaryGetValue(ourInfoDict, kCFBundleVersionKey);

					if (!ourVersion)
						NSLog(CFSTR("GrowlApplicationBridge: our property list does not contain a version; cannot compare agaist the installed Growl (description of our property list follows)\n%@"), ourInfoDict);
					else {
						CFDictionaryRef installedInfoDict = CFBundleGetInfoDictionary(growlPrefPaneBundle);
						CFStringRef installedVersion = CFDictionaryGetValue(installedInfoDict, kCFBundleVersionKey);

						if (!installedVersion) {
							NSLog(CFSTR("GrowlApplicationBridge: no installed version (description of installed prefpane's Info.plist follows)\n%@"), installedInfoDict);
							_Growl_ShowInstallationPrompt();
							//_Growl_ShowInstallationPrompt prints its own errors
						} else {
							Boolean upgradeIsAvailable = (compareVersionStringsTranslating1_0To0_5(ourVersion, installedVersion) == kCFCompareGreaterThan);

							if (upgradeIsAvailable && !promptedToUpgradeGrowl) {
								CFStringRef lastDoNotPromptVersion = CFPreferencesCopyAppValue(CFSTR("Growl Update:Do Not Prompt Again:Last Version"),
																							   kCFPreferencesCurrentApplication);

								if (!lastDoNotPromptVersion ||
									(compareVersionStringsTranslating1_0To0_5(ourVersion, lastDoNotPromptVersion) == kCFCompareGreaterThan))
								{
									OSStatus err = _Growl_ShowUpdatePromptForVersion(ourVersion);
									promptedToUpgradeGrowl = (err == noErr);
									//_Growl_ShowUpdatePromptForVersion prints its own errors
								}

								if (lastDoNotPromptVersion)
									CFRelease(lastDoNotPromptVersion);
							}
						} //if (installedVersion)
					} //if (ourVersion)

					CFRelease(ourInfoDict);
				} //if (ourInfoDict)

				CFRelease(ourInfoDictURL);
			} //if (ourInfoDictURL)
		} //if (frameworkBundle)
	} //if (growlPrefPaneBundle)
}
#endif

#pragma mark -
#pragma mark Notification callbacks

static void _growlIsReady(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object, userInfo)
	CFNotificationCenterRef distCenter = CFNotificationCenterGetDistributedCenter();

	//Stop observing
	CFNotificationCenterRemoveEveryObserver(distCenter, (void *)_growlIsReady);

	//since Growl is ready, it must be running.
	growlLaunched = true;

	if (targetsToNotifyArray) {
		for (CFIndex dictIndex = 0, numDicts = CFArrayGetCount(targetsToNotifyArray); dictIndex < numDicts; dictIndex++) {
			CFDictionaryRef infoDict = CFArrayGetValueAtIndex(targetsToNotifyArray, dictIndex);

			GrowlLaunchCallback callback = (GrowlLaunchCallback)CFDictionaryGetValue(infoDict, CFSTR("Callback"));
			void *context = (void *)CFDictionaryGetValue(infoDict, CFSTR("Context"));

			callback(context);
		}

		//Clear our tracking array
		CFRelease(targetsToNotifyArray); targetsToNotifyArray = NULL;
	}

	//register (fixes #102: this is necessary if we got here by Growl having just been installed)
	if (registerWhenGrowlIsReady) {
		Growl_Reregister();
		registerWhenGrowlIsReady = false;
	}

#ifdef GROWL_WITH_INSTALLER
	//flush queuedGrowlNotifications
	if (queuedGrowlNotifications) {
		for (CFIndex notificationIndex = 0, numNotifications = CFArrayGetCount(queuedGrowlNotifications); notificationIndex < numNotifications; ++notificationIndex) {
			CFDictionaryRef notificationDict = CFArrayGetValueAtIndex(queuedGrowlNotifications, notificationIndex);
			CFNotificationCenterPostNotification(distCenter,
												 GROWL_NOTIFICATION,
												 /*object*/ NULL,
												 notificationDict,
												 /*deliverImmediately*/ false);
		}

		CFRelease(queuedGrowlNotifications); queuedGrowlNotifications = NULL;
	}
#endif
}

static void _growlNotificationWasClicked(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object)
	if (delegate) {
		void (*growlNotificationWasClickedCallback)(CFPropertyListRef) = delegate->growlNotificationWasClicked;
		if (growlNotificationWasClickedCallback)
			growlNotificationWasClickedCallback(CFDictionaryGetValue(userInfo, GROWL_KEY_CLICKED_CONTEXT));
	}
}

static void _growlNotificationTimedOut(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
#pragma unused(center, observer, name, object)
	if (delegate) {
		void (*growlNotificationTimedOutCallback)(CFPropertyListRef) = delegate->growlNotificationTimedOut;
		if (growlNotificationTimedOutCallback) {
			growlNotificationTimedOutCallback(CFDictionaryGetValue(userInfo, GROWL_KEY_CLICKED_CONTEXT));
		}
	}
}
