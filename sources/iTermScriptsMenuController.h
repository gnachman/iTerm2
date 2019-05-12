//
//  iTermScriptsMenuController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermScriptItem : NSObject
@property (nonatomic, readonly, weak) iTermScriptItem *parent;
@property (nonatomic, readonly, strong) NSString *name;
@property (nonatomic, readonly, strong) NSString *path;
@property (nonatomic, readonly) BOOL isFolder;
@property (nonatomic, readonly) BOOL fullEnvironment;
@property (nonatomic, readonly) NSArray<iTermScriptItem *> *children;
@property (nonatomic, readonly) BOOL isAutoLaunchFolderItem;
@end

@interface iTermScriptsMenuController : NSObject

@property (nonatomic, strong) NSMenuItem *installRuntimeMenuItem;
@property (nonatomic, readonly) NSArray<NSString *> *allScripts;

- (NSArray<iTermScriptItem *> *)scriptItems;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMenu:(NSMenu *)menu;

- (void)build;
- (BOOL)runAutoLaunchScriptsIfNeeded;
- (void)revealScriptsInFinder;
- (void)newPythonScript;

- (void)launchScriptWithRelativePath:(NSString *)path
                  explicitUserAction:(BOOL)explicitUserAction;

- (void)launchScriptWithAbsolutePath:(NSString *)fullPath
                  explicitUserAction:(BOOL)explicitUserAction;
- (BOOL)couldLaunchScriptWithAbsolutePath:(NSString *)fullPath;

- (void)chooseAndExportScript;
- (void)chooseAndImportScript;

- (BOOL)scriptShouldAutoLaunchWithFullPath:(NSString *)fullPath;
- (void)moveScriptToAutoLaunch:(NSString *)fullPath;
- (BOOL)couldMoveScriptToAutoLaunch:(NSString *)fullPath;

- (void)importDidFinishWithErrorMessage:(NSString *)errorMessage
                               location:(NSURL *)location
                            originalURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END

