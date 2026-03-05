//
//  iTermNaggingController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/11/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSWindow;

extern NSString *const kTurnOffBracketedPasteOnHostChangeUserDefaultsKey;
extern NSString *const kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey;
extern NSString *const kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier;

@protocol iTermNaggingControllerDelegate<NSObject>
- (BOOL)naggingControllerCanShowMessageWithIdentifier:(NSString *)identifier;
- (void)naggingControllerShowMessage:(NSString *)message
                          isQuestion:(BOOL)isQuestion
                           important:(BOOL)important
                          identifier:(NSString *)identifier
                             options:(NSArray<NSString *> *)options
                          completion:(void (^)(int))completion;
- (void)naggingControllerShowMarkdownMessage:(NSString *)message
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
- (void)naggingControllerRestoreIconNameTo:(NSString *)iconName windowName:(NSString *)windowName;
- (void)naggingControllerCloseSession;
- (void)naggingControllerRepairInitialWorkingDirectoryOfSessionWithGUID:(NSString *)guid
                                                  inArrangementWithName:(NSString *)arrangementName;
- (void)naggingControllerDisableTriggersInInteractiveApps;
- (void)naggingControllerAssignProfileToSession:(NSString *)arrangementName
                                           guid:(NSString *)guid;
- (void)naggingControllerPrettyPrintJSON;
- (NSWindow * _Nullable)naggingControllerWindow;
- (void)naggingControllerSetProfileProperties:(NSDictionary *)dict;
- (BOOL)naggingControllerAnnouncementWouldObscureCursorForText:(NSString *)text;

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

- (void)sessionEndedWithExecFailure:(BOOL)execDidFail;

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
- (void)offerToRestoreIconName:(NSString *)iconName windowName:(NSString *)windowName;

- (BOOL)shouldAskAboutClearingScrollbackHistory;
- (void)askAboutClearingScrollbackHistory;
- (BOOL)terminalCanChangeProfile;
- (BOOL)tmuxWindowsShouldCloseAfterDetach;
- (void)arrangementWithName:(NSString *)arrangementName
              hasInvalidPWD:(NSString *)badPWD
         forSessionWithGuid:(NSString *)sessionGUID;
- (void)offerToDisableTriggersInInteractiveAppsWithStats:(NSString *)stats;
- (void)tmuxDidUpdatePasteBuffer;
- (void)openURL:(NSURL *)url;
- (void)openCommandDidFailWithSecureInputEnabled;
- (void)offerToFixSessionWithBrokenArrangementProfileIn:(NSString *)arrangementName
                                                   guid:(NSString *)guid;
- (void)showJSONPromotion;
- (void)offerTextReplacement:(void (^NS_NOESCAPE)(void))perform;
- (void)cancelTextReplacementOffer;
- (void)offerToSetProfileProperties:(NSDictionary *)dict;
- (void)offerToEnableTouchIDForSudo;
- (void)removeTouchIDForSudoOffer;

@end

NS_ASSUME_NONNULL_END
