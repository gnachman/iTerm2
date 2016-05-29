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

// This code has been altered.


#import "NSFileManager+iTerm.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAutoMasterParser.h"
#include <sys/param.h>
#include <sys/mount.h>

enum
{
    DirectoryLocationErrorNoPathFound,
    DirectoryLocationErrorFileExistsAtLocation
};
    
NSString * const DirectoryLocationDomain = @"DirectoryLocationDomain";

@implementation NSFileManager (iTerm)

/**
 * Locate a standard directory. Optionally append a subdirectory to the path. Create the chain
 * of directories if needed.
 *
 * @param searchPathDirectory Search path for @c NSSearchPathForDirectoriesInDomains.
 * @param domainMask Domain mask for @c NSSearchPathForDirectoriesInDomains
 * @param appendComponent Subdirectory to append to path. Optional.
 * @param errorOut Optional, will be set to NSError on failure
 *
 * @return Path or nil
 */
- (NSString *)findOrCreateDirectory:(NSSearchPathDirectory)searchPathDirectory
                           inDomain:(NSSearchPathDomainMask)domainMask
                appendPathComponent:(NSString *)appendComponent
                              error:(NSError **)errorOut {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(searchPathDirectory,
                                                         domainMask,
                                                         YES);
    if (!paths.count) {
        if (errorOut)         {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"No path found for directory in domain.",
                                        @"NSSearchPathDirectory": @(searchPathDirectory),
                                        @"NSSearchPathDomainMask": @(domainMask) };
            *errorOut = [NSError errorWithDomain:DirectoryLocationDomain
                                            code:DirectoryLocationErrorNoPathFound
                                        userInfo:userInfo];
        }
        return nil;
    }
    
    // Only the first one returned is interesting. Append subdirectory if needed.
    NSString *resolvedPath = paths[0];
    if (appendComponent) {
        resolvedPath = [resolvedPath stringByAppendingPathComponent:appendComponent];
    }
    
    // Create if needed.
    NSError *error = nil;
    BOOL success = [self createDirectoryAtPath:resolvedPath
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&error];
    if (!success)  {
        if (errorOut) {
            *errorOut = error;
        }
        return nil;
    }
    
    if (errorOut) {
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

- (NSString *)legacyApplicationSupportDirectory {
    NSError *error;
    NSString *result = [self findOrCreateDirectory:NSApplicationSupportDirectory
                                          inDomain:NSUserDomainMask
                               appendPathComponent:@"iTerm"
                                             error:&error];
    if (!result) {
        NSLog(@"Unable to find or create application support directory:\n%@", error);
    }
    return result;
}

- (NSString *)versionNumberFilename {
    return [[self legacyApplicationSupportDirectory] stringByAppendingPathComponent:@"version.txt"];
}

- (NSString *)scriptsPath {
    return [[self legacyApplicationSupportDirectory] stringByAppendingPathComponent:@"Scripts"];
}

- (NSString *)autolaunchScriptPath {
    return [[self scriptsPath] stringByAppendingPathComponent:@"AutoLaunch.scpt"];
}

- (NSString *)quietFilePath {
    return [[self legacyApplicationSupportDirectory] stringByAppendingPathComponent:@"quiet"];
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

- (BOOL)fileExistsAtPathLocally:(NSString *)filename
         additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkPaths {
    DLog(@"Additional network paths are: %@", additionalNetworkPaths);
    // Augment list of additional paths with nfs automounter mount points.
    NSMutableArray *networkPaths = [[additionalNetworkPaths mutableCopy] autorelease];
    [networkPaths addObjectsFromArray:[[iTermAutoMasterParser sharedInstance] mountpointsWithMap:@"auto_nfs"]];
    
    for (NSString *path in networkPaths) {
        if (!path.length) {
            continue;
        }
        if (![path hasSuffix:@"/"]) {
            path = [path stringByAppendingString:@"/"];
        }
        if ([filename hasPrefix:path]) {
            DLog(@"Filename %@ has prefix of ignored path %@", filename, path);
            return NO;
        }
    }

    struct statfs buf;
    int rc = statfs([filename UTF8String], &buf);
    if (rc != 0 || (buf.f_flags & MNT_LOCAL)) {
        return [self fileExistsAtPath:filename];
    } else {
        return NO;
    }
}

@end
