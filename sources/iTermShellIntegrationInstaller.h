//
//  iTermShellIntegrationInstaller.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import <Foundation/Foundation.h>

@protocol iTermShellIntegrationInstallerViewController <NSObject>
- (void)setBusy:(BOOL)busy;
@optional
- (void)willAppear;
@end

@protocol iTermShellIntegrationInstallerDelegate<NSObject>
- (void)shellIntegrationInstallerContinue;
- (void)shellIntegrationInstallerSetInstallUtilities:(BOOL)installUtilities;
- (void)shellIntegrationInstallerBack;
- (void)shellIntegrationInstallerCancel;
- (void)shellIntegrationInstallerConfirmDownloadAndRun;
- (void)shellIntegrationInstallerReallyDownloadAndRun;
- (void)shellIntegrationInstallerSendShellCommands:(int)stage;
- (void)shellIntegrationInstallerSkipStage;
- (NSString *)shellIntegrationInstallerNextCommandForSendShellCommands;
- (void)shellIntegrationInstallerCancelExpectations;
@end

typedef NS_ENUM(NSUInteger, iTermShellIntegrationShell) {
    iTermShellIntegrationShellBash,
    iTermShellIntegrationShellTcsh,
    iTermShellIntegrationShellZsh,
    iTermShellIntegrationShellFish,
    iTermShellIntegrationShellUnknown
};

extern NSString *iTermShellIntegrationShellString(iTermShellIntegrationShell shell);
