//
//  iTermScriptExporter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptExporter.h"

#import "iTermCommandRunner.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermSetupPyParser.h"
#import "NSFileManager+iTerm.h"

@implementation iTermScriptExporter

+ (NSURL *)urlForNewZipFileInFolder:(NSURL *)destinationFolder name:(NSString *)name {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *zipURL;
    NSInteger count = 0;
    do {
        count++;
        if (count == 1) {
            zipURL = [destinationFolder URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"zip"]];
        } else {
            NSString *nameWithCount = [NSString stringWithFormat:@"%@ (%@)", name, @(count)];
            zipURL = [destinationFolder URLByAppendingPathComponent:[nameWithCount stringByAppendingPathExtension:@"zip"]];
        }
    } while ([fileManager fileExistsAtPath:zipURL.path]);
    return zipURL;
}

+ (void)exportScriptAtURL:(NSURL *)fullURL completion:(void (^)(NSString *errorMessage, NSURL *zipURL))completion {
    NSURL *relativeURL = [self relativeURLFromFullURL:fullURL];
    if (!relativeURL) {
        completion(@"Invalid location (not under Scripts folder).", nil);
        return;
    }

    BOOL fullEnvironment = NO;
    if (![self urlContainsScript:fullURL fullEnvironment:&fullEnvironment]) {
        completion(@"No found script at selected location.", nil);
    }
    NSString *name = [fullURL.path lastPathComponent];
    if (!fullEnvironment) {
        NSString *scriptName = [name stringByDeletingPathExtension];
        NSString *temp = [[[NSFileManager defaultManager] temporaryDirectory] stringByAppendingPathComponent:scriptName];
        [[NSFileManager defaultManager] createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:NULL];
        [self copySimpleScriptAtURL:fullURL
                              named:[name stringByDeletingPathExtension]
                toFullEnvironmentIn:temp];
        NSURL *tempURL = [NSURL fileURLWithPath:temp];
        [self exportFullEnvironmentScriptAtURL:tempURL
                                   relativeURL:[NSURL fileURLWithPath:scriptName]
                                          name:scriptName
                                    completion:^(NSString *errorMessage, NSURL *zipURL) {
                                        [[NSFileManager defaultManager] removeItemAtPath:temp error:nil];
                                        completion(errorMessage, zipURL);
                                    }];
        return;
    }
    [self exportFullEnvironmentScriptAtURL:fullURL relativeURL:relativeURL name:name completion:completion];
}

+ (void)exportFullEnvironmentScriptAtURL:(NSURL *)fullURL
                             relativeURL:(NSURL *)relativeURL
                                    name:(NSString *)name
                              completion:(void (^)(NSString *errorMessage, NSURL *zipURL))completion {
    NSArray<NSURL *> *sourceURLs;
    NSURL *destinationFolder = [NSURL fileURLWithPath:[[NSFileManager defaultManager] desktopDirectory]];

    NSString *absSetupPath = [fullURL URLByAppendingPathComponent:@"setup.py"].path;
    iTermSetupPyParser *setupParser = [[iTermSetupPyParser alloc] initWithPath:absSetupPath];
    if (setupParser.dependenciesError) {
        completion(@"Could not parse install_requires in setup.py", nil);
        return;
    }

    sourceURLs = @[ [relativeURL URLByAppendingPathComponent:@"setup.py"],
                    [relativeURL URLByAppendingPathComponent:name] ];

    NSURL *zipURL = [self urlForNewZipFileInFolder:destinationFolder name:name];
    [iTermCommandRunner zipURLs:sourceURLs
                      arguments:@[ @"-r" ]
                       toZipURL:zipURL
                     relativeTo:fullURL.URLByDeletingLastPathComponent
                     completion:^(BOOL ok) {
                         completion(ok ? nil : @"Failed to create zip file.", zipURL);
                     }];
}

+ (void)copySimpleScriptAtURL:(NSURL *)simpleScriptSourceURL
                        named:(NSString *)name
          toFullEnvironmentIn:(NSString *)destination {
    [iTermSetupPyParser writeSetupPyToFile:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"setup.py"]]
                                      name:name
                              dependencies:@[]
                             pythonVersion:[iTermPythonRuntimeDownloader latestPythonVersion]];
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
        // Legal scripts must have a setup.py, iterm2env, and appropriately named source folder and file.
        NSString *setupPy = [url.path stringByAppendingPathComponent:@"setup.py"];
        NSString *iterm2env = [url.path stringByAppendingPathComponent:@"iterm2env"];
        NSString *name = url.path.lastPathComponent;
        NSString *folder = [url.path stringByAppendingPathComponent:name];
        NSString *mainPy = [folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];

        if  ([fileManager fileExistsAtPath:setupPy] &&
             [fileManager fileExistsAtPath:iterm2env] &&
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
    NSString *prefix = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingString:@"/"];
    if (![full.path hasPrefix:prefix]) {
        return nil;
    }
    NSString *suffix = [full.path substringFromIndex:prefix.length];
    return [NSURL fileURLWithPath:suffix];
}

@end
