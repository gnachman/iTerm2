//
//  iTermShellIntegrationPasteShellCommandsViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import <Cocoa/Cocoa.h>
#import "iTermShellIntegrationInstaller.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermShellIntegrationPasteShellCommandsViewController : NSViewController<iTermShellIntegrationInstallerViewController>

@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic) int stage;
@property (nonatomic) iTermShellIntegrationShell shell;
@property (nonatomic) BOOL installUtilities;
// The last attempt at the current stage's step reported that it failed: the shell integration
// script was not written, or the utility scripts were not extracted. Cleared when the stage
// changes.
@property (nonatomic) BOOL writeFailed;
// Discovery ran in a helper shell a canceled install left running rather than in the user's
// shell. Cleared when the stage changes.
@property (nonatomic) BOOL discoveryFoundHelperShell;
// Exposed for testing.
@property (nonatomic, readonly) NSTextField *stepListField;

- (void)update;

@end


NS_ASSUME_NONNULL_END
