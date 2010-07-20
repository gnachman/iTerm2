//
//  CFGrowlAdditions.c
//  Growl
//
//  Created by Mac-arena the Bored Zo on Wed Jun 18 2004.
//  Copyright 2005 The Growl Project.
//

#include <Carbon/Carbon.h>
#include "CFGrowlAdditions.h"
#include <c.h>
#include <unistd.h>

static CFStringRef _CFURLAliasDataKey  = CFSTR("_CFURLAliasData");
static CFStringRef _CFURLStringKey     = CFSTR("_CFURLString");
static CFStringRef _CFURLStringTypeKey = CFSTR("_CFURLStringType");

//see GrowlApplicationBridge-Carbon.c for rationale of using NSLog.
extern void NSLog(CFStringRef format, ...);

CFStringRef copyCurrentProcessName(void) {
	ProcessSerialNumber PSN = { 0, kCurrentProcess };
	CFStringRef name = NULL;
	OSStatus err = CopyProcessName(&PSN, &name);
	if (err != noErr) {
		NSLog(CFSTR("in copyCurrentProcessName in CFGrowlAdditions: Could not get process name because CopyProcessName returned %li"), (long)err);
		name = NULL;
	}
	return name;
}

CFURLRef copyCurrentProcessURL(void) {
	ProcessSerialNumber psn = { 0, kCurrentProcess };
	FSRef fsref;
	CFURLRef URL = NULL;
	OSStatus err = GetProcessBundleLocation(&psn, &fsref);
	if (err != noErr) {
		NSLog(CFSTR("in copyCurrentProcessURL in CFGrowlAdditions: Could not get application location, because GetProcessBundleLocation returned %li\n"), (long)err);
	} else {
		URL = CFURLCreateFromFSRef(kCFAllocatorDefault, &fsref);
	}
	return URL;
}
CFStringRef copyCurrentProcessPath(void) {
	CFURLRef URL = copyCurrentProcessURL();
	CFStringRef path = CFURLCopyFileSystemPath(URL, kCFURLPOSIXPathStyle);
	CFRelease(URL);
	return path;
}

CFURLRef copyTemporaryFolderURL(void) {
	FSRef ref;
	CFURLRef url = NULL;

	OSStatus err = FSFindFolder(kOnAppropriateDisk, kTemporaryFolderType, kCreateFolder, &ref);
	if (err != noErr)
		NSLog(CFSTR("in copyTemporaryFolderPath in CFGrowlAdditions: Could not locate temporary folder because FSFindFolder returned %li"), (long)err);
	else
		url = CFURLCreateFromFSRef(kCFAllocatorDefault, &ref);

	return url;
}
CFStringRef copyTemporaryFolderPath(void) {
	CFStringRef path = NULL;

	CFURLRef url = copyTemporaryFolderURL();
	if (url) {
		path = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
		CFRelease(url);
	}

	return path;
}

CFDictionaryRef createDockDescriptionForURL(CFURLRef url) {
	if (!url) {
		NSLog(CFSTR("%@"), CFSTR("in copyDockDescriptionForURL in CFGrowlAdditions: Cannot copy Dock description for a NULL URL"));
		return NULL;
	}

	//return NULL for non-file: URLs.
	CFStringRef scheme = CFURLCopyScheme(url);
	Boolean isFileURL = (CFStringCompare(scheme, CFSTR("file"), kCFCompareCaseInsensitive) == kCFCompareEqualTo);
	CFRelease(scheme);
	if (!isFileURL)
		return NULL;

	CFDictionaryRef dict = NULL;
	CFStringRef path     = NULL;
	CFDataRef aliasData  = NULL;

	FSRef    fsref;
	if (CFURLGetFSRef(url, &fsref)) {
		AliasHandle alias = NULL;
		OSStatus    err   = FSNewAlias(/*fromFile*/ NULL, &fsref, &alias);
		if (err != noErr) {
			NSLog(CFSTR("in copyDockDescriptionForURL in CFGrowlAdditions: FSNewAlias for %@ returned %li"), url, (long)err);
		} else {
			HLock((Handle)alias);

			err = FSCopyAliasInfo(alias, /*targetName*/ NULL, /*volumeName*/ NULL, (CFStringRef *)&path, /*whichInfo*/ NULL, /*info*/ NULL);
			if (err != noErr) {
				NSLog(CFSTR("in copyDockDescriptionForURL in CFGrowlAdditions: FSCopyAliasInfo for %@ returned %li"), url, (long)err);
			}

			aliasData = CFDataCreate(kCFAllocatorDefault, (UInt8 *)*alias, GetHandleSize((Handle)alias));

			HUnlock((Handle)alias);
			DisposeHandle((Handle)alias);
		}
	}

	if (!path) {
		path = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
	}

	if (path || aliasData) {
		CFMutableDictionaryRef temp = CFDictionaryCreateMutable(kCFAllocatorDefault, /*capacity*/ 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

		if (path) {
			CFDictionarySetValue(temp, _CFURLStringKey, path);
			CFRelease(path);

			int pathStyle = kCFURLPOSIXPathStyle;
			CFNumberRef pathStyleNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pathStyle);
			CFDictionarySetValue(temp, _CFURLStringTypeKey, pathStyleNum);
			CFRelease(pathStyleNum);
		}

		if (aliasData) {
			CFDictionarySetValue(temp, _CFURLAliasDataKey, aliasData);
			CFRelease(aliasData);
		}

		dict = temp;
	}

	return dict;
}

CFDataRef copyIconDataForPath(CFStringRef path) {
	CFDataRef data = NULL;

	//false is probably safest, and is harmless when the object really is a directory.
	CFURLRef URL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path, kCFURLPOSIXPathStyle, /*isDirectory*/ false);
	if (URL) {
		data = copyIconDataForURL(URL);
		CFRelease(URL);
	}

	return data;
}
CFDataRef copyIconDataForURL(CFURLRef URL) {
	CFDataRef data = NULL;

	if (URL) {
		FSRef ref;
		if (CFURLGetFSRef(URL, &ref)) {
			IconRef icon = NULL;
			SInt16 label_noOneCares;
			OSStatus err = GetIconRefFromFileInfo(&ref,
												  /*inFileNameLength*/ 0U, /*inFileName*/ NULL,
												  kFSCatInfoNone, /*inCatalogInfo*/ NULL,
												  kIconServicesNoBadgeFlag | kIconServicesUpdateIfNeededFlag,
												  &icon,
												  &label_noOneCares);
			if (err != noErr) {
				NSLog(CFSTR("in copyIconDataForURL in CFGrowlAdditions: could not get icon for %@: GetIconRefFromFileInfo returned %li\n"), URL, (long)err);
			} else {
				IconFamilyHandle fam = NULL;
				err = IconRefToIconFamily(icon, kSelectorAllAvailableData, &fam);
				if (err != noErr) {
					NSLog(CFSTR("in copyIconDataForURL in CFGrowlAdditions: could not get icon for %@: IconRefToIconFamily returned %li\n"), URL, (long)err);
				} else {
					HLock((Handle)fam);
					data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)*(Handle)fam, GetHandleSize((Handle)fam));
					HUnlock((Handle)fam);
					DisposeHandle((Handle)fam);
				}
				ReleaseIconRef(icon);
			}
		}
	}

	return data;
}

URL_TYPE createURLByMakingDirectoryAtURLWithName(URL_TYPE parent, STRING_TYPE name) {
	CFURLRef newDirectory = NULL;

	CFAllocatorRef allocator = parent ? CFGetAllocator(parent) : name ? CFGetAllocator(name) : kCFAllocatorDefault;

	if (parent) parent = CFRetain(parent);
	else {
		char *cwdBytes = alloca(PATH_MAX);
		getcwd(cwdBytes, PATH_MAX);
		parent = CFURLCreateFromFileSystemRepresentation(allocator, (const unsigned char *)cwdBytes, strlen(cwdBytes), /*isDirectory*/ true);
		if (!name) {
			newDirectory = parent;
			goto end;
		}
	}
	if (!parent)
		NSLog(CFSTR("in createURLByMakingDirectoryAtURLWithName in CFGrowlAdditions: parent directory URL is NULL (please tell the Growl developers)\n"), parent);
	else {
		if (name)
			name = CFRetain(name);
		else {
			name = CFURLCopyLastPathComponent(parent);
			CFURLRef newParent = CFURLCreateCopyDeletingLastPathComponent(allocator, parent);
			CFRelease(parent);
			parent = newParent;
		}

		if (!name)
			NSLog(CFSTR("in createURLByMakingDirectoryAtURLWithName in CFGrowlAdditions: name of directory to create is NULL (please tell the Growl developers)\n"), parent);
		else {
			FSRef parentRef;
			if (!CFURLGetFSRef(parent, &parentRef))
				NSLog(CFSTR("in createURLByMakingDirectoryAtURLWithName in CFGrowlAdditions: could not create FSRef for parent directory at %@ (please tell the Growl developers)\n"), parent);
			else {
				FSRef newDirectoryRef;

				struct HFSUniStr255 nameUnicode;
				CFRange range = { 0, MIN(CFStringGetLength(name), USHRT_MAX) };
				CFStringGetCharacters(name, range, nameUnicode.unicode);
				nameUnicode.length = range.length;

				struct FSRefParam refPB = {
					.ref              = &parentRef,
					.nameLength       = nameUnicode.length,
					.name             = nameUnicode.unicode,
					.whichInfo        = kFSCatInfoNone,
					.catInfo          = NULL,
					.textEncodingHint = kTextEncodingUnknown,
					.newRef           = &newDirectoryRef,
				};
				
				OSStatus err = PBCreateDirectoryUnicodeSync(&refPB);
				if (err == dupFNErr) {
					//dupFNErr == file (or folder) exists already. this is fine.
					err = PBMakeFSRefUnicodeSync(&refPB);
				}
				if (err == noErr) {
					NSLog(CFSTR("PBCreateDirectoryUnicodeSync or PBMakeFSRefUnicodeSync returned %li; calling CFURLCreateFromFSRef"), (long)err); //XXX
					newDirectory = CFURLCreateFromFSRef(allocator, &newDirectoryRef);
					NSLog(CFSTR("CFURLCreateFromFSRef returned %@"), newDirectory); //XXX
				} else
					NSLog(CFSTR("in createURLByMakingDirectoryAtURLWithName in CFGrowlAdditions: could not create directory '%@' in parent directory at %@: FSCreateDirectoryUnicode returned %li (please tell the Growl developers)"), name, parent, (long)err);
			}

			CFRelease(parent);
		} //if (name)
		CFRelease(name);
	} //if (parent)

end:
	return newDirectory;
}

#ifndef COPYFORK_BUFSIZE
#	define COPYFORK_BUFSIZE 5242880U /*5 MiB*/
#endif

static OSStatus copyFork(const struct HFSUniStr255 *forkName, const FSRef *srcFile, const FSRef *destDir, const struct HFSUniStr255 *destName, FSRef *outDestFile) {
	OSStatus err, closeErr;
	struct FSForkIOParam srcPB = {
		.ref = srcFile,
		.forkNameLength = forkName->length,
		.forkName = forkName->unicode,
		.permissions = fsRdPerm,
	};
	unsigned char debuggingPathBuf[PATH_MAX] = "";
	OSStatus debuggingPathErr;

	err = PBOpenForkSync(&srcPB);
	if (err != noErr) {
		debuggingPathErr = FSRefMakePath(srcFile, debuggingPathBuf, PATH_MAX);
		if (debuggingPathErr != noErr)
			snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for source file: FSRefMakePath returned %li)", (long)debuggingPathErr);
		NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBOpenForkSync (source: %s) returned %li"), debuggingPathBuf, (long)err);
	} else {
		FSRef destFile;

		/*the first thing to do is get the name of the destination file, if one
		 *	wasn't provided.
		 *and while we're at it, we get the catalogue info as well.
		 */
		struct FSCatalogInfo catInfo;
		struct FSRefParam refPB = {
			.ref       = srcFile,
			.whichInfo = kFSCatInfoGettableInfo & kFSCatInfoSettableInfo,
			.catInfo   = &catInfo,
			.spec      = NULL,
			.parentRef = NULL,
			.outName   = destName ? NULL : (struct HFSUniStr255 *)(destName = alloca(sizeof(struct HFSUniStr255))),
		};

		err = PBGetCatalogInfoSync(&refPB);
		if (err != noErr) {
			debuggingPathErr = FSRefMakePath(srcFile, debuggingPathBuf, PATH_MAX);
			if (debuggingPathErr != noErr)
				snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for source file: FSRefMakePath returned %li)", (long)debuggingPathErr);
			NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBGetCatalogInfoSync (source: %s) returned %li"), debuggingPathBuf, (long)err);
		} else {
			refPB.ref              = destDir;
			refPB.nameLength       = destName->length;
			refPB.name             = destName->unicode;
			refPB.textEncodingHint = kTextEncodingUnknown;
			refPB.newRef           = &destFile;

			const char *functionName = "PBMakeFSRefUnicodeSync"; //for error-reporting message

			err = PBMakeFSRefUnicodeSync(&refPB);
			if ((err != noErr) && (err != fnfErr)) {
			handleMakeFSRefError:
				debuggingPathErr = FSRefMakePath(destDir, debuggingPathBuf, PATH_MAX);
				if (debuggingPathErr != noErr)
					snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for destination directory: FSRefMakePath returned %li)", (long)debuggingPathErr);

				//get filename too
				CFStringRef debuggingFilename = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault,
																				   destName->unicode,
																				   destName->length,
																				   /*contentsDeallocator*/ kCFAllocatorNull);
				if (!debuggingFilename)
					debuggingFilename = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, "(could not get filename for destination file: CFStringCreateWithCharactersNoCopy returned NULL)", kCFStringEncodingASCII, /*contentsDeallocator*/ kCFAllocatorNull);

				NSLog(CFSTR("in copyFork in CFGrowlAdditions: %s (destination: %s/%@) returned %li"), functionName, debuggingPathBuf, debuggingFilename, (long)err);

				if (debuggingFilename) CFRelease(debuggingFilename);
			} else {
				//that file doesn't exist in that folder; create it.
				err = PBCreateFileUnicodeSync(&refPB);
				if (err == noErr) {
					/*make sure the Finder knows about the new file.
					 *FNNotify returns a status code too, but this isn't an
					 *	essential step, so we just ignore it.
					 */
					FNNotify(destDir, kFNDirectoryModifiedMessage, kNilOptions);
				} else if (err == dupFNErr) {
					/*dupFNErr: the file already exists.
					 *we can safely ignore this error.
					 */
					err = noErr;
				} else {
					functionName = "PBCreateFileUnicodeSync";
					goto handleMakeFSRefError;
				}
			}
		}
		if (err == noErr) {
			if (outDestFile)
				memcpy(outDestFile, &destFile, sizeof(destFile));

			struct FSForkIOParam destPB = {
				.ref            = &destFile,
				.forkNameLength = forkName->length,
				.forkName       = forkName->unicode,
				.permissions    = fsWrPerm,
			};
			err = PBOpenForkSync(&destPB);
			NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBOpenForkSync (dest) returned %li"), (long)err);
			if (err != noErr) {
				debuggingPathErr = FSRefMakePath(&destFile, debuggingPathBuf, PATH_MAX);
				if (debuggingPathErr != noErr)
					snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for dest file: FSRefMakePath returned %li)", (long)debuggingPathErr);
				NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBOpenForkSync (destination: %s) returned %li"), debuggingPathBuf, (long)err);
			} else {
				void *buf = malloc(COPYFORK_BUFSIZE);
				if (buf) {
					srcPB.buffer = destPB.buffer = buf;
					srcPB.requestCount = COPYFORK_BUFSIZE;
					while (err == noErr) {
						err = PBReadForkSync(&srcPB);
						if (err == eofErr) {
							err = noErr;
							if (srcPB.actualCount == 0)
								break;
						}
						if (err != noErr) {
							debuggingPathErr = FSRefMakePath(&destFile, debuggingPathBuf, PATH_MAX);
							if (debuggingPathErr != noErr)
								snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for source file: FSRefMakePath returned %li)", (long)debuggingPathErr);
							NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBReadForkSync (source: %s) returned %li"), debuggingPathBuf, (long)err);
						} else {
							destPB.requestCount = srcPB.actualCount;
							err = PBWriteForkSync(&destPB);
							if (err != noErr) {
								debuggingPathErr = FSRefMakePath(&destFile, debuggingPathBuf, PATH_MAX);
								if (debuggingPathErr != noErr)
									snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for dest file: FSRefMakePath returned %li)", (long)debuggingPathErr);
								NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBWriteForkSync (destination: %s) returned %li"), debuggingPathBuf, (long)err);
							}
						}
					}

					free(buf);
				}

				closeErr = PBCloseForkSync(&destPB);
				if (closeErr != noErr) {
					debuggingPathErr = FSRefMakePath(&destFile, debuggingPathBuf, PATH_MAX);
					if (debuggingPathErr != noErr)
						snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for dest file: FSRefMakePath returned %li)", (long)debuggingPathErr);
					NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBCloseForkSync (destination: %s) returned %li"), debuggingPathBuf, (long)err);
				}
				if (err == noErr) err = closeErr;
			}
		}

		closeErr = PBCloseForkSync(&srcPB);
		if (closeErr != noErr) {
			debuggingPathErr = FSRefMakePath(&destFile, debuggingPathBuf, PATH_MAX);
			if (debuggingPathErr != noErr)
				snprintf((char *)debuggingPathBuf, PATH_MAX, "(could not get path for source file: FSRefMakePath returned %li)", (long)debuggingPathErr);
			NSLog(CFSTR("in copyFork in CFGrowlAdditions: PBCloseForkSync (source: %s) returned %li"), debuggingPathBuf, (long)err);
		}
		if (err == noErr) err = closeErr;
	}

	return err;
}

static OSStatus GrowlCopyObjectSync(const FSRef *fileRef, const FSRef *destRef, FSRef *destFileRef) {
	OSStatus err;
	struct HFSUniStr255 forkName;
	struct FSForkIOParam forkPB = {
		.ref = fileRef,
		.forkIterator = {
			.initialize = 0L
		},
		.outForkName = &forkName,
	};
	
	do {
		err = PBIterateForksSync(&forkPB);
		NSLog(CFSTR("PBIterateForksSync returned %li"), (long)err);
		if (err != noErr) {
			if (err != errFSNoMoreItems)
				NSLog(CFSTR("in GrowlCopyObjectSync in CFGrowlAdditions: PBIterateForksSync returned %li"), (long)err);
		} else {
			err = copyFork(&forkName, fileRef, destRef, /*destName*/ NULL, /*outDestFile*/ destFileRef);
			//copyFork prints its own error messages
		}
	} while (err == noErr);
	if (err == errFSNoMoreItems) err = noErr;

	return err;
}

CFURLRef createURLByCopyingFileFromURLToDirectoryURL(CFURLRef file, CFURLRef dest) {
	CFURLRef destFileURL = NULL;

	FSRef fileRef, destRef, destFileRef;
	Boolean gotFileRef = CFURLGetFSRef(file, &fileRef);
	Boolean gotDestRef = CFURLGetFSRef(dest, &destRef);
	if (!gotFileRef)
		NSLog(CFSTR("in createURLByCopyingFileFromURLToDirectoryURL in CFGrowlAdditions: CFURLGetFSRef failed with source URL %@"), file);
	else if (!gotDestRef)
		NSLog(CFSTR("in createURLByCopyingFileFromURLToDirectoryURL in CFGrowlAdditions: CFURLGetFSRef failed with destination URL %@"), dest);
	else {
		OSStatus err;

		/*
		 * 10.2 has a problem with weak symbols in frameworks so we use
		 * MAC_OS_X_VERSION_MIN_REQUIRED >= 10.3.
		 */
#if defined(NSAppKitVersionNumber10_3) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_3
		if (FSCopyObjectSync) {
			err = FSCopyObjectSync(&fileRef, &destRef, /*destName*/ NULL, &destFileRef, kFSFileOperationOverwrite);
		} else {
#endif
			err = GrowlCopyObjectSync(&fileRef, &destRef, &destFileRef);
#if defined(NSAppKitVersionNumber10_3) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_3
		}
#endif

		if (err == noErr)
			destFileURL = CFURLCreateFromFSRef(kCFAllocatorDefault, &destFileRef);
		else
			NSLog(CFSTR("in createURLByCopyingFileFromURLToDirectoryURL in CFGrowlAdditions: CopyObjectSync returned %li for source URL %@"), (long)err, file);
	}

	return destFileURL;
}

CFPropertyListRef createPropertyListFromURL(CFURLRef file, u_int32_t mutability, CFPropertyListFormat *outFormat, CFStringRef *outErrorString) {
	CFPropertyListRef plist = NULL;

	if (!file)
		NSLog(CFSTR("in createPropertyListFromURL in CFGrowlAdditions: cannot read from a NULL URL"));
	else {
		CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, file);
		if (!stream)
			NSLog(CFSTR("in createPropertyListFromURL in CFGrowlAdditions: could not create stream for reading from URL %@"), file);
		else {
			if (!CFReadStreamOpen(stream))
				NSLog(CFSTR("in createPropertyListFromURL in CFGrowlAdditions: could not open stream for reading from URL %@"), file);
			else {
				CFPropertyListFormat format;
				CFStringRef errorString = NULL;

				plist = CFPropertyListCreateFromStream(kCFAllocatorDefault,
													   stream,
													   /*streamLength*/ 0,
													   mutability,
													   &format,
													   &errorString);
				if (!plist)
					NSLog(CFSTR("in createPropertyListFromURL in CFGrowlAdditions: could not read property list from URL %@ (error string: %@)"), file, errorString);

				if (outFormat) *outFormat = format;
				if (errorString) {
					if (outErrorString)
						*outErrorString = errorString;
					else
						CFRelease(errorString);
				}

				CFReadStreamClose(stream);
			}

			CFRelease(stream);
		}
	}

	return plist;
}
