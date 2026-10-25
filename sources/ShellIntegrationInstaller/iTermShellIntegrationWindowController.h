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
// Stop typing text sent with shellIntegrationWindowControllerSendText: that has not been typed
// yet, such as the rest of a long paste.
- (void)shellIntegrationWindowControllerStopSendingText;
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
@property (nonatomic, readonly) NSTextField *sendShellCommandsStepListField;
// The command the helper sh runs in the utilities folder to receive and unpack the archive.
@property (class, nonatomic, readonly) NSString *receiveUtilitiesCommand;
// The command that makes the helper sh enter the utilities folder and says whether it did.
+ (NSString *)commandToEnterUtilitiesFolder:(NSString *)folder NS_SWIFT_NAME(commandToEnterUtilitiesFolder(_:));
@end

NS_ASSUME_NONNULL_END
