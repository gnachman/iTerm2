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
// The last attempt to write the shell integration script reported that the file was not
// written. Cleared when the stage changes.
@property (nonatomic) BOOL writeFailed;
// Exposed for testing.
@property (nonatomic, readonly) NSTextField *stepListField;

- (void)update;

@end


NS_ASSUME_NONNULL_END
