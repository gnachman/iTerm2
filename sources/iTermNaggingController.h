//
//  iTermNaggingController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/11/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kTurnOffBracketedPasteOnHostChangeUserDefaultsKey;
extern NSString *const kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier;

@protocol iTermNaggingControllerDelegate<NSObject>
- (BOOL)naggingControllerCanShowMessageWithIdentifier:(NSString *)identifier;
- (void)naggingControllerShowMessage:(NSString *)message
                          isQuestion:(BOOL)isQuestion
                           important:(BOOL)important
                          identifier:(NSString *)identifier
                             options:(NSArray<NSString *> *)options
                          completion:(void (^)(int))completion;

- (void)naggingControllerRepairSavedArrangement:(NSString *)savedArrangementName
                            missingProfileNamed:(NSString *)profileName
                                           guid:(NSString *)guid;

- (void)naggingControllerRemoveMessageWithIdentifier:(NSString *)identifier;

- (void)naggingControllerRestart;
- (void)naggingControllerAbortDownload;
- (void)naggingControllerAbortUpload;
- (void)naggingControllerSetBackgroundImageToFileWithName:(nullable NSString *)filename;
- (void)naggingControllerDisableMouseReportingPermanently:(BOOL)permanently;
- (void)naggingControllerDisableBracketedPasteMode;
- (void)naggingControllerCloseSession;
- (void)naggingControllerRepairInitialWorkingDirectoryOfSessionWithGUID:(NSString *)guid
                                                  inArrangementWithName:(NSString *)arrangementName;
- (void)naggingControllerDisableTriggersInInteractiveApps;

@end

@interface iTermNaggingController : NSObject
@property (nonatomic, weak) id<iTermNaggingControllerDelegate> delegate;

// If we have complained that the saved arrangement is missing a profile, this is the GUID of the
// missing profile.
@property (nonatomic, copy, readonly) NSString *missingSavedArrangementProfileGUID;


- (BOOL)permissionToReportVariableNamed:(NSString *)name;

- (void)arrangementWithName:(NSString *)savedArrangementName
        missingProfileNamed:(NSString *)profileName
                       guid:(NSString *)guid;
- (void)didRepairSavedArrangement;

- (void)brokenPipe;

- (void)didRestoreOrphan;
- (void)willRecycleSession;

- (void)askAboutAbortingDownload;
- (void)askAboutAbortingUpload;
- (void)didFinishDownload;

- (void)tmuxSupplementaryPlaneErrorForCharacter:(NSString *)string;
- (void)tryingToSendArrowKeysWithScrollWheel:(BOOL)isTrying;

- (void)setBackgroundImageToFileWithName:(NSString *)filename;
- (void)didDetectMouseReportingFrustration;

- (void)offerToTurnOffBracketedPasteOnHostChange;

- (BOOL)shouldAskAboutClearingScrollbackHistory;
- (void)askAboutClearingScrollbackHistory;
- (BOOL)terminalCanChangeProfile;
- (BOOL)tmuxWindowsShouldCloseAfterDetach;
- (void)arrangementWithName:(NSString *)arrangementName
              hasInvalidPWD:(NSString *)badPWD
         forSessionWithGuid:(NSString *)sessionGUID;
- (void)offerToDisableTriggersInInteractiveApps;
- (void)tmuxDidUpdatePasteBuffer;
- (void)openURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
