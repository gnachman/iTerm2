//
//  NSFileManager+DirectoryLocations.m
//
//  Created by Matt Gallagher on 06 May 2010
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

#import "NSFileManager+iTerm.h"
#include <sys/param.h>
#include <sys/mount.h>

enum
{
	DirectoryLocationErrorNoPathFound,
	DirectoryLocationErrorFileExistsAtLocation
};
	
NSString * const DirectoryLocationDomain = @"DirectoryLocationDomain";

@implementation NSFileManager (iTerm)

//
// findOrCreateDirectory:inDomain:appendPathComponent:error:
//
// Method to tie together the steps of:
//	1) Locate a standard directory by search path and domain mask
//  2) Select the first path in the results
//	3) Append a subdirectory to that path
//	4) Create the directory and intermediate directories if needed
//	5) Handle errors by emitting a proper NSError object
//
// Parameters:
//    searchPathDirectory - the search path passed to NSSearchPathForDirectoriesInDomains
//    domainMask - the domain mask passed to NSSearchPathForDirectoriesInDomains
//    appendComponent - the subdirectory appended
//    errorOut - any error from file operations
//
// returns the path to the directory (if path found and exists), nil otherwise
//
- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
	inDomain:(NSSearchPathDomainMask)domainMask
	appendPathComponent:(NSString *)appendComponent
	error:(NSError **)errorOut
{
	//
	// Search for the path
	//
	NSArray* paths = NSSearchPathForDirectoriesInDomains(
		searchPathDirectory,
		domainMask,
		YES);
	if ([paths count] == 0)
	{
		if (errorOut)
		{
			NSDictionary *userInfo =
				[NSDictionary dictionaryWithObjectsAndKeys:
					NSLocalizedStringFromTable(
						@"No path found for directory in domain.",
						@"Errors",
					nil),
					NSLocalizedDescriptionKey,
					[NSNumber numberWithInteger:searchPathDirectory],
					@"NSSearchPathDirectory",
					[NSNumber numberWithInteger:domainMask],
					@"NSSearchPathDomainMask",
				nil];
			*errorOut =
				[NSError 
					errorWithDomain:DirectoryLocationDomain
					code:DirectoryLocationErrorNoPathFound
					userInfo:userInfo];
		}
		return nil;
	}
	
	//
	// Normally only need the first path returned
	//
	NSString *resolvedPath = [paths objectAtIndex:0];

	//
	// Append the extra path component
	//
	if (appendComponent)
	{
		resolvedPath = [resolvedPath
			stringByAppendingPathComponent:appendComponent];
	}
	
	//
	// Create the path if it doesn't exist
	//
	NSError *error = nil;
	BOOL success = [self
		createDirectoryAtPath:resolvedPath
		withIntermediateDirectories:YES
		attributes:nil
		error:&error];
	if (!success) 
	{
		if (errorOut)
		{
			*errorOut = error;
		}
		return nil;
	}
	
	//
	// If we've made it this far, we have a success
	//
	if (errorOut)
	{
		*errorOut = nil;
	}
	return resolvedPath;
}

//
// applicationSupportDirectory
//
// Returns the path to the applicationSupportDirectory (creating it if it doesn't
// exist).
//
- (NSString *)applicationSupportDirectory {
    NSString *executableName =
        [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleExecutableKey];
    NSError *error;
    NSString *result = [self findOrCreateDirectory:NSApplicationSupportDirectory
                                          inDomain:NSUserDomainMask
                               appendPathComponent:executableName
                                             error:&error];
    if (!result) {
        NSLog(@"Unable to find or create application support directory:\n%@", error);
    }
    return result;
}

- (NSString *)temporaryDirectory {
    // Create a unique directory in the system temporary directory
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:guid];
    if (![self createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]) {
        return nil;
    }
    return path;
}

- (NSString *)desktopDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

- (BOOL)directoryIsWritable:(NSString *)dir
{
    if ([[dir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
        return NO;
    }
    
    NSString *filename = [NSString stringWithFormat:@"%@/.testwritable.%d", dir, (int)getpid()];
    NSError *error = nil;
    [@"test" writeToFile:filename
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:&error];
    if (error) {
        return NO;
    }
    unlink([filename UTF8String]);
    return YES;
}

- (BOOL)fileExistsAtPathLocally:(NSString *)filename {
    struct statfs buf;
    int rc = statfs([filename UTF8String], &buf);
    if (rc != 0 || (buf.f_flags & MNT_LOCAL)) {
        return [self fileExistsAtPath:filename];
    } else {
        return NO;
    }
}

@end
