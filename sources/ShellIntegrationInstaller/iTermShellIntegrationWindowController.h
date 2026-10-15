//
//  iTermShellIntegrationWindowController.h
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import <Cocoa/Cocoa.h>
#import "iTermShellIntegrationInstaller.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermExpect;

@protocol iTermShellIntegrationWindowControllerDelegate<NSObject>
- (void)shellIntegrationWindowControllerSendText:(NSString *)text;
- (iTermExpect *)shellIntegrationExpect;
@end

@interface iTermShellIntegrationWindowController : NSWindowController<iTermShellIntegrationInstallerDelegate>
@property (nonatomic, weak) id<iTermShellIntegrationWindowControllerDelegate> delegate;

// Exposed for testing.
@property (nonatomic, readonly) iTermShellIntegrationShell shell;
@property (nullable, nonatomic, readonly, copy) NSString *dotdir;
@property (nonatomic, readonly) int sendShellCommandsStage;
@property (nonatomic, readonly) BOOL sendShellCommandsWriteFailed;
@property (nonatomic, readonly) BOOL showingDownloadAndRunPage;
@property (nonatomic, readonly) BOOL showingSendShellCommandsPage;
@end

NS_ASSUME_NONNULL_END
