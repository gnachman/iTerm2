//
//  iTermScriptArchive.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptArchive.h"

#import "iTermPythonRuntimeDownloader.h"
#import "iTermSetupPyParser.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"

NSString *const iTermScriptSetupPyName = @"setup.py";
NSString *const iTermScriptMetadataName = @"metadata.json";

@interface iTermScriptArchive()
@property (nonatomic, copy, readwrite) NSString *container;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, strong, readwrite) NSDictionary *metadata;
@property (nonatomic, readwrite) BOOL fullEnvironment;
@end

@implementation iTermScriptArchive

+ (instancetype)archiveForScriptIn:(NSString *)container
                             named:(NSString *)name
                   fullEnvironment:(BOOL)fullEnvironment {
    iTermScriptArchive *archive = [[self alloc] init];
    archive.container = container.copy;
    archive.name = name.copy;
    archive.fullEnvironment = fullEnvironment;
    archive.metadata = [self metadataInContainer:container name:name];
    return archive;
}

+ (NSDictionary *)metadataInContainer:(NSString *)container name:(NSString *)name {
    NSString *path = [[container stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"metadata.json"];
    NSString *stringValue = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!stringValue) {
        return nil;
    }
    return [NSDictionary castFrom:[NSJSONSerialization it_objectForJsonString:stringValue]];
}

+ (NSArray<NSString *> *)absolutePathsOfNonDotFilesIn:(NSString *)container {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *topLevelItems = [fileManager it_itemsInDirectory:container];
    topLevelItems = [topLevelItems filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return ![anObject hasPrefix:@"."];
    }];
    topLevelItems = [topLevelItems mapWithBlock:^id(NSString *anObject) {
        return [container stringByAppendingPathComponent:anObject];
    }];
    return topLevelItems;
}

+ (instancetype)archiveFromContainer:(NSString *)container {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *topLevelItems = [self absolutePathsOfNonDotFilesIn:container];
    if (topLevelItems.count != 1) {
        return nil;
    }

    NSString *topLevelItem = topLevelItems.firstObject;
    const BOOL topLevelItemIsDirectory = [fileManager itemIsDirectory:topLevelItem];
    if ([[topLevelItem pathExtension] isEqualToString:@"py"] &&
        !topLevelItemIsDirectory &&
        [topLevelItem isEqualToString:[container stringByAppendingPathComponent:topLevelItem.lastPathComponent]]) {
        // Basic script
        return [iTermScriptArchive archiveForScriptIn:container named:topLevelItems[0].lastPathComponent fullEnvironment:NO];
    }
    if (!topLevelItemIsDirectory) {
        // File not ending in .py
        return nil;
    }

    NSArray<NSString *> *innerItems = [self absolutePathsOfNonDotFilesIn:topLevelItem];
    if (innerItems.count < 2) {
        return nil;
    }
    // Maps a boolean number to an item name. True key = setup.py, false key = not setup.py
    NSString *setupPy = [topLevelItem stringByAppendingPathComponent:iTermScriptSetupPyName];
    NSString *metadata = [topLevelItem stringByAppendingPathComponent:iTermScriptMetadataName];
    NSArray<NSString *> *requiredFiles = @[ setupPy ];
    NSArray<NSString *> *optionalFiles = @[ metadata ];
    NSString *folder = nil;

    for (NSString *item in innerItems) {
        if ([requiredFiles containsObject:item]) {
            requiredFiles = [requiredFiles arrayByRemovingObject:item];
            continue;
        }
        if ([optionalFiles containsObject:item]) {
            continue;
        }
        if (folder == nil && [fileManager itemIsDirectory:item]) {
            folder = item;
            continue;
        }
        return nil;
    }
    if (!folder || requiredFiles.count) {
        return nil;
    }
    NSString *name = [folder lastPathComponent];
    BOOL isDirectory;
    // mainPy="dir/name/name.py"
    NSString *mainPy = [[topLevelItem stringByAppendingPathComponent:name] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];
    if (![fileManager fileExistsAtPath:mainPy isDirectory:&isDirectory] ||
        isDirectory) {
        return nil;
    }

    return [iTermScriptArchive archiveForScriptIn:container named:name fullEnvironment:YES];
}

- (BOOL)wantsAutoLaunch {
    return [[NSNumber castFrom:self.metadata[@"AutoLaunch"]] boolValue];
}

- (BOOL)userAcceptsAutoLaunchInstall {
    NSString *body = [NSString stringWithFormat:@"“%@” would like to run automatically when iTerm2 starts. Would you like to allow that?", self.name];
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:body
                                                                       actions:@[ @"Allow", @"Decline" ]
                                                                     accessory:nil
                                                                    identifier:nil
                                                                   silenceable:kiTermWarningTypePersistent
                                                                       heading:@"Allow Auto-Launch?"
                                                                        window:nil];
    return (selection == kiTermWarningSelection0);
}

- (void)installTrusted:(BOOL)trusted withCompletion:(void (^)(NSError *))completion {
    if (self.fullEnvironment) {
        [self installFullEnvironmentTrusted:trusted completion:completion];
    } else {
        [self installBasicTrusted:trusted completion:completion];
    }
}

- (void)installBasicTrusted:(BOOL)trusted completion:(void (^)(NSError *))completion {
    NSString *from = [self.container stringByAppendingPathComponent:self.name];
    NSString *to;
    if (trusted && [self wantsAutoLaunch] && [self userAcceptsAutoLaunchInstall]) {
        to = [[[NSFileManager defaultManager] autolaunchScriptPath] stringByAppendingPathComponent:self.name];
    } else {
        to = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:self.name];
    }
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtPath:from
                                            toPath:to
                                             error:&error];
    completion(error);
}

- (void)installFullEnvironmentTrusted:(BOOL)trusted completion:(void (^)(NSError *))completion {
    NSString *from = [self.container stringByAppendingPathComponent:self.name];

    NSString *setupPy = [from stringByAppendingPathComponent:iTermScriptSetupPyName];
    iTermSetupPyParser *setupParser = [[iTermSetupPyParser alloc] initWithPath:setupPy];
    if (!setupParser) {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Cannot find setup.py" };
        NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:1 userInfo:userInfo];
        completion(error);
        return;
    }

    NSArray<NSString *> *dependencies = setupParser.dependencies;
    if (setupParser.dependenciesError) {
        completion(setupParser.dependenciesError);
        return;
    }

    // You always get the iterm2 module so don't bother to pip install it.
    dependencies = [dependencies arrayByRemovingObject:@"iterm2"];
    NSString *to;
    if (trusted && [self wantsAutoLaunch] && [self userAcceptsAutoLaunchInstall]) {
        to = [[[NSFileManager defaultManager] autolaunchScriptPath] stringByAppendingPathComponent:self.name];
    } else {
        to = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:self.name];
    }
    [[iTermPythonRuntimeDownloader sharedInstance] downloadOptionalComponentsIfNeededWithConfirmation:YES
                                                                                        pythonVersion:setupParser.pythonVersion
                                                                                       withCompletion:
     ^(BOOL downloadedOk) {
         if (!downloadedOk) {
             NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Python Runtime not downloaded" };
             NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:3 userInfo:userInfo];
             completion(error);
             return;
         }
         [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:[NSURL fileURLWithPath:from]
                                                                     pythonVersion:setupParser.pythonVersion
                                                                      dependencies:dependencies
                                                                     createSetupPy:NO
                                                                        completion:^(BOOL ok) {
                                                                            [self didInstallPythonRuntime:ok
                                                                                                     from:from
                                                                                                       to:to
                                                                                               completion:completion];
                                                                        }];
     }];
}

- (void)didInstallPythonRuntime:(BOOL)ok
                           from:(NSString *)from
                             to:(NSString *)to
                     completion:(void (^)(NSError *))completion {
    if (!ok) {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Failed to install Python Runtime" };
        NSError *error = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:1 userInfo:userInfo];
        completion(error);
        return;
    }

    // Finally, move it to its destination.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    [fileManager moveItemAtPath:from
                         toPath:to
                          error:&error];
    completion(error);
}

@end

