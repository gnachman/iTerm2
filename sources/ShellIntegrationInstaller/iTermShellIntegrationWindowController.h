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

// How long to wait, after a cancel, for helper shells whose launch was typed but not yet seen to
// prompt, so they can be exited. Once it passes nothing is typed. Settable for testing.
@property (nonatomic) NSTimeInterval canceledHelperLaunchTimeout;
// Exposed for testing: waiting, after a cancel, for launched helper shells to prompt.
@property (nonatomic, readonly) BOOL waitingForCanceledHelperLaunch;

// Call on a new installer for the same session as previous. Until helper shells that previous
// left running have exited (or it stops waiting for them), discovery waits for them, so it asks
// the user's shell rather than a helper.
- (void)takeOverHelperShellsFromInstaller:(nullable iTermShellIntegrationWindowController *)previous;

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
// Matches the prompt of the innermost helper sh, as the installer waits for it.
@property (class, nonatomic, readonly) NSString *helperPromptRegex;
// The command that makes the helper sh enter the utilities folder and says whether it did.
+ (NSString *)commandToEnterUtilitiesFolder:(NSString *)folder NS_SWIFT_NAME(commandToEnterUtilitiesFolder(_:));
@end

NS_ASSUME_NONNULL_END
