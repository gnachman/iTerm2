//
//  iTermAPIScriptLauncher.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermAPIScriptLauncher : NSObject

// Launches an API script. Reads its output and waits for it to terminate.
+ (void)launchScript:(NSString *)filename
           arguments:(NSArray<NSString *> *)arguments
  explicitUserAction:(BOOL)explicitUserAction;

+ (void)launchScript:(NSString *)filename
            fullPath:(NSString *)fullPath
           arguments:(NSArray<NSString *> *)arguments
      withVirtualEnv:(NSString *)virtualenv
        setupCfgPath:(NSString *)setupCfgPath
  explicitUserAction:(BOOL)explicitUserAction;

+ (NSString *)environmentForScript:(NSString *)path
                      checkForMain:(BOOL)checkForMain
                     checkForSaved:(BOOL)checkForSaved;
// If path is the inner main.py of a full-environment script (Foo/Foo/Foo.py with a valid
// environment at Foo), returns the container Foo; otherwise nil. Lets a launch by the
// inner .py path (stale index / Open Quickly / direct) still use the full environment.
+ (NSString *)fullEnvironmentContainerForMainPyPath:(NSString *)path;
+ (NSString *)prospectivePythonPathForPyenvScriptNamed:(NSString *)name;
+ (NSString *)pathToVersionsFolderForPyenvScriptNamed:(NSString *)name;
+ (NSString *)inferredPythonVersionFromScriptAt:(NSString *)path;

@end
