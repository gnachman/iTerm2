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
  explicitUserAction:(BOOL)explicitUserAction;

+ (void)launchScript:(NSString *)filename
            fullPath:(NSString *)fullPath
      withVirtualEnv:(NSString *)virtualenv
        setupCfgPath:(NSString *)setupCfgPath
  explicitUserAction:(BOOL)explicitUserAction;

+ (NSString *)environmentForScript:(NSString *)path checkForMain:(BOOL)checkForMain;
+ (NSString *)prospectivePythonPathForPyenvScriptNamed:(NSString *)name;

@end
