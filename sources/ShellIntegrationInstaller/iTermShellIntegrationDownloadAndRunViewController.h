//
//  iTermShellIntegrationDownloadAndRunViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import <Cocoa/Cocoa.h>
#import "iTermShellIntegrationInstaller.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermShellIntegrationDownloadAndRunViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic) BOOL installUtilities;
@property (nonatomic) BOOL busy;
@property (nonatomic, readonly) NSString *urlString;
@property (nonatomic, readonly) NSString *command;

- (void)showShellUnsupportedError;

@end

NS_ASSUME_NONNULL_END
