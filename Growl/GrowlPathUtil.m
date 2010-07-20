//
//  GrowlPathUtil.m
//  Growl
//
//  Created by Ingmar Stein on 17.04.05.
//  Copyright 2005 The Growl Project. All rights reserved.
//
// This file is under the BSD License, refer to License.txt for details

#import "GrowlPathUtil.h"

#define HelperAppBundleIdentifier				@"com.Growl.GrowlHelperApp"
#define GROWL_PREFPANE_BUNDLE_IDENTIFIER		@"com.growl.prefpanel"
#define GROWL_PREFPANE_NAME						@"Growl.prefPane"
#define PREFERENCE_PANES_SUBFOLDER_OF_LIBRARY	@"PreferencePanes"
#define PREFERENCE_PANE_EXTENSION				@"prefPane"

static NSBundle *helperAppBundle;
static NSBundle *prefPaneBundle;

@implementation GrowlPathUtil

+ (NSBundle *) growlPrefPaneBundle {
	NSArray			*librarySearchPaths;
	NSString		*path;
	NSString		*bundleIdentifier;
	NSEnumerator	*searchPathEnumerator;
	NSBundle		*bundle;

	if (prefPaneBundle) {
		return prefPaneBundle;
	}

	static const unsigned bundleIDComparisonFlags = NSCaseInsensitiveSearch | NSBackwardsSearch;

	//Find Library directories in all domains except /System (as of Panther, that's ~/Library, /Library, and /Network/Library)
	librarySearchPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask & ~NSSystemDomainMask, YES);

	/*First up, we'll have a look for Growl.prefPane, and if it exists, check
	 *	whether it is our prefPane.
	 *This is much faster than having to enumerate all preference panes, and
	 *	can drop a significant amount of time off this code.
	 */
	searchPathEnumerator = [librarySearchPaths objectEnumerator];
	while ((path = [searchPathEnumerator nextObject])) {
		path = [path stringByAppendingPathComponent:PREFERENCE_PANES_SUBFOLDER_OF_LIBRARY];
		path = [path stringByAppendingPathComponent:GROWL_PREFPANE_NAME];

		if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
			bundle = [NSBundle bundleWithPath:path];

			if (bundle) {
				bundleIdentifier = [bundle bundleIdentifier];

				if (bundleIdentifier && ([bundleIdentifier compare:GROWL_PREFPANE_BUNDLE_IDENTIFIER options:bundleIDComparisonFlags] == NSOrderedSame)) {
					prefPaneBundle = bundle;
					return prefPaneBundle;
				}
			}
		}
	}

	/*Enumerate all installed preference panes, looking for the Growl prefpane
	 *	bundle identifier and stopping when we find it.
	 *Note that we check the bundle identifier because we should not insist
	 *	that the user not rename his preference pane files, although most users
	 *	of course will not.  If the user wants to mutilate the Info.plist file
	 *	inside the bundle, he/she deserves to not have a working Growl
	 *	installation.
	 */
	searchPathEnumerator = [librarySearchPaths objectEnumerator];
	while ((path = [searchPathEnumerator nextObject])) {
		NSString				*bundlePath;
		NSDirectoryEnumerator   *bundleEnum;

		path = [path stringByAppendingPathComponent:PREFERENCE_PANES_SUBFOLDER_OF_LIBRARY];
		bundleEnum = [[NSFileManager defaultManager] enumeratorAtPath:path];

		while ((bundlePath = [bundleEnum nextObject])) {
			if ([[bundlePath pathExtension] isEqualToString:PREFERENCE_PANE_EXTENSION]) {
				bundle = [NSBundle bundleWithPath:[path stringByAppendingPathComponent:bundlePath]];

				if (bundle) {
					bundleIdentifier = [bundle bundleIdentifier];

					if (bundleIdentifier && ([bundleIdentifier compare:GROWL_PREFPANE_BUNDLE_IDENTIFIER options:bundleIDComparisonFlags] == NSOrderedSame)) {
						prefPaneBundle = bundle;
						return prefPaneBundle;
					}
				}

				[bundleEnum skipDescendents];
			}
		}
	}

	return nil;
}

#pragma mark -
#pragma mark Important file-system objects

+ (NSBundle *) helperAppBundle {
	if (!helperAppBundle) {
		NSBundle *bundle = [NSBundle mainBundle];
		if ([[bundle bundleIdentifier] isEqualToString:HelperAppBundleIdentifier]) {
			//we are running in GHA.
			helperAppBundle = bundle;
		} else {
			//look in the prefpane bundle.
			bundle = [NSBundle bundleForClass:[GrowlPathUtil class]];
			if (![[bundle bundleIdentifier] isEqualToString:GROWL_PREFPANE_BUNDLE_IDENTIFIER]) {
				bundle = [GrowlPathUtil growlPrefPaneBundle];
			}
			NSString *helperAppPath = [bundle pathForResource:@"GrowlHelperApp" ofType:@"app"];
			helperAppBundle = [NSBundle bundleWithPath:helperAppPath];
		}
	}
	return helperAppBundle;
}

+ (NSString *) growlSupportDir {
	NSString *supportDir;
	NSArray *searchPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, /* expandTilde */ YES);

	supportDir = [searchPath objectAtIndex:0U];
	supportDir = [supportDir stringByAppendingPathComponent:@"Application Support/Growl"];

	return supportDir;
}

#pragma mark -

+ (NSString *) screenshotsDirectory {
	NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Growl/Screenshots"];
	[[NSFileManager defaultManager] createDirectoryAtPath:path
											   attributes:nil];
	return path;
}

+ (NSString *) nextScreenshotName {
	NSFileManager *mgr = [NSFileManager defaultManager];

	NSString *directory = [GrowlPathUtil screenshotsDirectory];
	NSString *filename = nil;

	NSArray *origContents = [mgr directoryContentsAtPath:directory];
	NSMutableSet *directoryContents = [[NSMutableSet alloc] initWithCapacity:[origContents count]];

	NSEnumerator *filesEnum = [origContents objectEnumerator];
	NSString *existingFilename;
	while ((existingFilename = [filesEnum nextObject])) {
		existingFilename = [directory stringByAppendingPathComponent:[existingFilename stringByDeletingPathExtension]];
		[directoryContents addObject:existingFilename];
	}

    unsigned long i;
	for (i = 1UL; i < ULONG_MAX; ++i) {
		[filename release];
		filename = [[NSString alloc] initWithFormat:@"Screenshot %lu", i];
		NSString *path = [directory stringByAppendingPathComponent:filename];
		if (![directoryContents containsObject:path]) {
			break;
		}
	}
	[directoryContents release];

	return [filename autorelease];
}

@end
