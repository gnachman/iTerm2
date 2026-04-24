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
+ (NSString *)prospectivePythonPathForPyenvScriptNamed:(NSString *)name;
+ (NSString *)pathToVersionsFolderForPyenvScriptNamed:(NSString *)name;
+ (NSString *)inferredPythonVersionFromScriptAt:(NSString *)path;

@end
