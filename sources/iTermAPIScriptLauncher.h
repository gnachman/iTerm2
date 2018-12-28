//
//  iTermAPIScriptLauncher.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermAPIScriptLauncher : NSObject

// Launches an API script. Reads its output and waits for it to terminate.
+ (void)launchScript:(NSString *)filename;

+ (void)launchScript:(NSString *)filename
            fullPath:(NSString *)fullPath
      withVirtualEnv:(NSString *)virtualenv
         setupPyPath:(NSString *)setupPyPath;

+ (NSString *)environmentForScript:(NSString *)path checkForMain:(BOOL)checkForMain;
+ (NSString *)prospectivePythonPathForPyenvScriptNamed:(NSString *)name;

@end
