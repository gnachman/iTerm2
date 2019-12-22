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

- (void)update;

@end


NS_ASSUME_NONNULL_END
