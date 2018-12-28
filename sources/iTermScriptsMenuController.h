//
//  iTermScriptsMenuController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermScriptsMenuController : NSObject

@property (nonatomic, strong) NSMenuItem *installRuntimeMenuItem;
@property (nonatomic, readonly) NSArray<NSString *> *allScripts;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMenu:(NSMenu *)menu;

- (void)build;
- (BOOL)runAutoLaunchScriptsIfNeeded;
- (void)revealScriptsInFinder;
- (void)newPythonScript;

- (void)launchScriptWithRelativePath:(NSString *)path;

- (void)launchScriptWithAbsolutePath:(NSString *)fullPath;
- (BOOL)couldLaunchScriptWithAbsolutePath:(NSString *)fullPath;

- (void)chooseAndExportScript;
- (void)chooseAndImportScript;

- (BOOL)scriptShouldAutoLaunchWithFullPath:(NSString *)fullPath;
- (void)moveScriptToAutoLaunch:(NSString *)fullPath;
- (BOOL)couldMoveScriptToAutoLaunch:(NSString *)fullPath;

@end

NS_ASSUME_NONNULL_END

