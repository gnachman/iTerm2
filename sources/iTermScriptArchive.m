//
//  iTermScriptArchive.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermScriptArchive.h"

#import "iTermPythonRuntimeDownloader.h"
#import "iTermSetupPyParser.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "RegexKitLite.h"

NSString *const iTermScriptSetupPyName = @"setup.py";

@interface iTermScriptArchive()
@property (nonatomic, copy, readwrite) NSString *container;
@property (nonatomic, copy, readwrite) NSString *name;
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
    return archive;
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
    if (innerItems.count != 2) {
        return nil;
    }
    // Maps a boolean number to an item name. True key = setup.py, false key = not setup.py
    NSString *setupPy = [topLevelItem stringByAppendingPathComponent:iTermScriptSetupPyName];
    NSDictionary<NSNumber *, NSArray<NSString *> *> *classified = [innerItems classifyWithBlock:^id(NSString *item) {
        NSString *fullPath = [container stringByAppendingPathComponent:iTermScriptSetupPyName];
        return @([item isEqualToString:setupPy] && ![fileManager itemIsDirectory:fullPath]);
    }];
    if (classified[@YES].count != 1) {
        return nil;
    }
    if (classified[@NO].count != 1) {
        return nil;
    }
    NSString *name = [classified[@NO].firstObject lastPathComponent];
    BOOL isDirectory;
    // mainPy="dir/name/name.py"
    NSString *mainPy = [[topLevelItem stringByAppendingPathComponent:name] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"py"]];
    if (![fileManager fileExistsAtPath:mainPy isDirectory:&isDirectory] ||
        isDirectory) {
        return nil;
    }

    return [iTermScriptArchive archiveForScriptIn:container named:name fullEnvironment:YES];
}

- (void)installWithCompletion:(void (^)(NSError *))completion {
    if (self.fullEnvironment) {
        [self installFullEnvironmentWithCompletion:completion];
    } else {
        [self installBasicWithCompletion:completion];
    }
}

- (void)installBasicWithCompletion:(void (^)(NSError *))completion {
    NSString *from = [self.container stringByAppendingPathComponent:self.name];
    NSString *to = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:self.name];
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtPath:from
                                            toPath:to
                                             error:&error];
    completion(error);
}

- (void)installFullEnvironmentWithCompletion:(void (^)(NSError *))completion {
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
    NSString *to = [[[NSFileManager defaultManager] scriptsPath] stringByAppendingPathComponent:self.name];
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

