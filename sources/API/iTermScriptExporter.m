//
//  iTermScriptExporter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptExporter.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermCommandRunner.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermSetupCfgParser.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "SIGArchiveBuilder.h"

@implementation iTermScriptExporter

+ (NSURL *)urlForNewZipFileInFolder:(NSURL *)destinationFolder name:(NSString *)name extension:(NSString *)extension {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *zipURL;
    NSInteger count = 0;
    do {
        count++;
        if (count == 1) {
            zipURL = [destinationFolder URLByAppendingPathComponent:[name stringByAppendingPathExtension:extension]];
        } else {
            NSString *nameWithCount = [NSString stringWithFormat:@"%@ (%@)", name, @(count)];
            zipURL = [destinationFolder URLByAppendingPathComponent:[nameWithCount stringByAppendingPathExtension:extension]];
        }
    } while ([fileManager fileExistsAtPath:zipURL.path]);
    return zipURL;
}

+ (void)exportScriptAtURL:(NSURL *)fullURL
          signingIdentity:(SIGIdentity *)sigIdentity
            callbackQueue:(dispatch_queue_t)callbackQueue
              destination:(NSURL *)destination
               autolaunch:(BOOL)autolaunch
               completion:(void (^)(NSString *errorMessage, NSURL *zipURL))completion {
    NSURL *relativeURL = [self relativeURLFromFullURL:fullURL];
    if (!relativeURL) {
        completion(@"Invalid location (not under Scripts folder).", nil);
        return;
    }

    BOOL fullEnvironment = NO;
    if (![self urlContainsScript:fullURL fullEnvironment:&fullEnvironment]) {
        completion(@"No found script at selected location.", nil);
        return;
    }
    NSString *name = [fullURL.path lastPathComponent];
    if (!fullEnvironment) {
        NSString *scriptName = [name stringByDeletingPathExtension];
        NSString *temp = [[[NSFileManager defaultManager] it_temporaryDirectory] stringByAppendingPathComponent:scriptName];
        [[NSFileManager defaultManager] createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:NULL];
        [self copySimpleScriptAtURL:fullURL
                              named:[name stringByDeletingPathExtension]
                toFullEnvironmentIn:temp];
        [self writeMetadataTo:[NSURL fileURLWithPath:temp]
                    sourceURL:fullURL
                   autolaunch:autolaunch];
        NSURL *tempURL = [NSURL fileURLWithPath:temp];
        [self exportFullEnvironmentScriptAtURL:tempURL
                                   relativeURL:[NSURL fileURLWithPath:scriptName]
                                          name:scriptName
                               signingIdentity:sigIdentity
                                 callbackQueue:callbackQueue
                                   destination:destination
                                    completion:^(NSString *errorMessage, NSURL *zipURL) {
                                        [[NSFileManager defaultManager] removeItemAtPath:temp error:nil];
                                        completion(errorMessage, zipURL);
                                    }];
        return;
    }

    // Export full environment script
    [self writeMetadataTo:fullURL
                sourceURL:fullURL
               autolaunch:autolaunch];
    [self exportFullEnvironmentScriptAtURL:fullURL
                               relativeURL:relativeURL
                                      name:name
                           signingIdentity:sigIdentity
                             callbackQueue:callbackQueue
                               destination:destination
                                completion:completion];
}

+ (void)writeMetadataTo:(NSURL *)destinationURL
              sourceURL:(NSURL *)sourceURL
             autolaunch:(BOOL)autolaunch {
    NSDictionary *metadata = @{ @"AutoLaunch": @(autolaunch) };
    [[NSJSONSerialization it_jsonStringForObject:metadata] writeToURL:[destinationURL URLByAppendingPathComponent:@"metadata.json"]
                                                           atomically:NO
                                                             encoding:NSUTF8StringEncoding
                                                                error:nil];
}

+ (void)exportFullEnvironmentScriptAtURL:(NSURL *)fullURL
                             relativeURL:(NSURL *)relativeURL
                                    name:(NSString *)name
                         signingIdentity:(SIGIdentity *)signingIdentity
                           callbackQueue:(dispatch_queue_t)callbackQueue
                             destination:(NSURL *)destination
                              completion:(void (^)(NSString *errorMessage, NSURL *zipURL))completion {
    NSArray<NSURL *> *sourceURLs;
    NSURL *destinationFolder = [NSURL fileURLWithPath:[[NSFileManager defaultManager] desktopDirectory]];

    NSString *absSetupPath = [fullURL URLByAppendingPathComponent:@"setup.cfg"].path;
    iTermSetupCfgParser *setupParser = [[iTermSetupCfgParser alloc] initWithPath:absSetupPath];
    if (setupParser.dependenciesError) {
        completion(@"Could not parse install_requires in setup.cfg", nil);
        return;
    }

    sourceURLs = @[ [relativeURL URLByAppendingPathComponent:@"setup.cfg"],
                    [relativeURL URLByAppendingPathComponent:name] ];
    NSURL *metadata = [relativeURL URLByAppendingPathComponent:@"metadata.json"];
    if (signingIdentity) {
        sourceURLs = [sourceURLs arrayByAddingObject:metadata];
    }

    NSString *extension = signingIdentity ? @"its" : @"zip";
    NSURL *zipURL = destination ?: [self urlForNewZipFileInFolder:destinationFolder name:name extension:extension];
    [iTermCommandRunner zipURLs:sourceURLs
                      arguments:@[ @"-r" ]
                       toZipURL:zipURL
                     relativeTo:fullURL.URLByDeletingLastPathComponent
                  callbackQueue:callbackQueue
                     completion:^(BOOL ok) {
                         if (!ok) {
                             completion(@"Failed to create zip file.", nil);
                             return;
                         }
                         if (signingIdentity) {
                             [self signInPlace:zipURL withIdentity:signingIdentity completion:^(NSError *signingError) {
                                 if (signingError) {
                                     completion(signingError.localizedDescription, nil);
                                     return;
                                 }
                                 completion(nil, zipURL);
                             }];
                             return;
                         }
                         completion(nil, zipURL);
                     }];
}

+ (void)signInPlace:(NSURL *)url
       withIdentity:(SIGIdentity *)identity
         completion:(void (^)(NSError *))completion {
    NSError *error = nil;
    NSURL *payloadURL = [url URLByAppendingPathExtension:[[NSUUID UUID] UUIDString]];
    BOOL ok = [[NSFileManager defaultManager] moveItemAtURL:url
                                                      toURL:payloadURL
                                                      error:&error];
    if (!ok || error) {
        completion(error);
        return;
    }

    SIGArchiveBuilder *builder = [[SIGArchiveBuilder alloc] initWithPayloadFileURL:payloadURL identity:identity];
    [builder writeToURL:url error:&error];
    [[NSFileManager defaultManager] removeItemAtURL:payloadURL error:nil];
    completion(error);
}

+ (void)copySimpleScriptAtURL:(NSURL *)simpleScriptSourceURL
                        named:(NSString *)name
          toFullEnvironmentIn:(NSString *)destination {
    // latestPythonVersion is nil on a uv-only machine (no legacy runtime installed).
    // writeSetupCfgToFile asserts on a nil pythonVersion (asserts are on in release),
    // so fall back to the shared default. The value is only a hint recorded in the
    // exported setup.cfg; a uv-based import re-resolves it, so any current build imports
    // this fine. LIMITATION: a LEGACY (pre-uv) build importing this archive asks its
    // legacy runtime downloader for exactly this minor, and if it is newer than any the
    // legacy manifest offers (e.g. 3.12 exported from a uv-only machine), that import
    // fails with RequestedVersionNotFound. We keep the default rather than silently
    // lowering it (there is no reliable way to know the legacy manifest's set from a
    // uv-only machine, and lowering it would change the default for the common case).
    NSString *pythonVersion = [iTermPythonRuntimeDownloader latestPythonVersion] ?: [iTermScriptRuntime defaultPythonVersion];
    [iTermSetupCfgParser writeSetupCfgToFile:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"setup.cfg"]]
                                        name:name
                                dependencies:@[]
                         ensureiTerm2Present:YES
                               pythonVersion:pythonVersion
                          environmentVersion:[[iTermPythonRuntimeDownloader sharedInstance] installedVersionWithPythonVersion:pythonVersion]];
    NSString *sourceFolder = [destination stringByAppendingPathComponent:name];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:sourceFolder
           withIntermediateDirectories:NO
                            attributes:nil
                                 error:NULL];
    NSURL *destinationPy = [NSURL fileURLWithPath:[sourceFolder stringByAppendingPathComponent:[simpleScriptSourceURL lastPathComponent]]];
    [fileManager copyItemAtURL:simpleScriptSourceURL
                         toURL:destinationPy
                         error:NULL];
    [fileManager setAttributes:@{ NSFilePosixPermissions: @(0744)}
                  ofItemAtPath:destinationPy.path
                         error:NULL];
}

+ (BOOL)urlContainsScript:(NSURL *)url fullEnvironment:(out nullable BOOL *)fullEnvironment {
    BOOL isDirectory = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:url.path isDirectory:&isDirectory]) {
        return NO;
    }
    if ([url.pathExtension isEqualToString:@"py"] && !isDirectory) {
        if (fullEnvironment) {
            *fullEnvironment = NO;
        }
        return YES;
    }
    if (isDirectory) {
        // Legal full-environment scripts have a setup.cfg, an appropriately named
        // source folder and file, and a runtime environment. The runtime is either the
        // legacy iterm2env tree or (for uv-provisioned/migrated scripts) the
        // python-runtime.json marker beside a .venv. The environment itself is rebuilt
        // on import, so it is not part of the archive; here we only need to recognize
        // the script.
        NSString *setupCfg = [url.path stringByAppendingPathComponent:@"setup.cfg"];
        NSString *iterm2env = [url.path stringByAppendingPathComponent:@"iterm2env"];
        NSString *uvMarker = [url.path stringByAppendingPathComponent:[iTermScriptRuntime markerFileName]];
        NSString *name = url.path.lastPathComponent;
        NSString *folder = [url.path stringByAppendingPathComponent:name];
        NSString *mainPy = [folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];

        const BOOL hasRuntime = [fileManager fileExistsAtPath:iterm2env] || [fileManager fileExistsAtPath:uvMarker];
        if  ([fileManager fileExistsAtPath:setupCfg] &&
             hasRuntime &&
             [fileManager fileExistsAtPath:mainPy]) {
            if (fullEnvironment) {
                *fullEnvironment = YES;
            }
            return YES;
        }
    }
    return NO;
}

+ (BOOL)urlIsScript:(NSURL *)url {
    return [self urlContainsScript:url fullEnvironment:nil];
}

+ (NSURL *)relativeURLFromFullURL:(NSURL *)full {
    return [NSURL fileURLWithPath:[full lastPathComponent]];
}

@end
