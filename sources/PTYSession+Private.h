//
//  PTYSession+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/27/21.
//
#import "PTYSession.h"

#import "Coprocess.h"
#import "SessionView.h"
#import "TerminalFile.h"
#import "TmuxController.h"
#import "Trigger.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAutomaticProfileSwitcher.h"
#import "iTermBackgroundDrawingHelper.h"
#import "iTermBadgeLabel.h"
#import "iTermColorMap.h"
#import "iTermComposerManager.h"
#import "iTermCopyModeHandler.h"
#import "iTermExpect.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermLoggingHelper.h"
#import "iTermMetaFrustrationDetector.h"
#import "iTermMetalGlue.h"
#import "iTermModifyOtherKeysMapper.h"
#import "iTermNaggingController.h"
#import "iTermObject.h"
#import "iTermPasteHelper.h"
#import "iTermSessionHotkeyController.h"
#import "iTermSessionNameController.h"
#import "iTermStandardKeyMapper.h"
#import "iTermStatusBarViewController.h"
#import "iTermTermkeyKeyMapper.h"
#import "iTermUpdateCadenceController.h"
#import "iTermWorkingDirectoryPoller.h"

@class PTYSessionPublishRequest;
@class iTermComposerManager;
@class iTermConductor;
@class AITermControllerObjC;

@interface PTYSession () <
iTermAutomaticProfileSwitcherDelegate,
iTermBackgroundDrawingHelperDelegate,
iTermBadgeLabelDelegate,
iTermCoprocessDelegate,
iTermCopyModeHandlerDelegate,
iTermConductorDelegate,
iTermComposerManagerDelegate,
iTermFilterDestination,
iTermHotKeyNavigableSession,
iTermImmutableColorMapDelegate,
iTermIntervalTreeObserver,
iTermLogging,
iTermMetaFrustrationDetector,
iTermMetalGlueDelegate,
iTermModernKeyMapperDelegate,
iTermModifyOtherKeysMapperDelegate,
iTermNaggingControllerDelegate,
iTermObject,
iTermPasteHelperDelegate,
iTermPasteboardReporterDelegate,
iTermSessionNameControllerDelegate,
iTermSessionViewDelegate,
iTermShortcutNavigationModeHandlerDelegate,
iTermStandardKeyMapperDelegate,
iTermStatusBarViewControllerDelegate,
iTermTailFindControllerDelegate,
iTermTermkeyKeyMapperDelegate,
iTermTriggersDataSource,
iTermTmuxControllerSession,
iTermUpdateCadenceControllerDelegate,
iTermSessionDirectoryTrackerDelegate,
TriggerDelegate> {
    // Changes are made in the main thread to this and it periodically copied to the mutation thread.
    iTermExpect *_expect;

    BOOL _havePendingPublish;
    NSMutableArray<PTYSessionPublishRequest *> *_pendingPublishRequests;
    iTermComposerManager *_composerManager;
    iTermAppSwitchingPreventionDetector *_appSwitchingPreventionDetector;
    AITermControllerObjC *_aiterm;
}

@property(nonatomic, retain) Interval *currentMarkOrNotePosition;
@property(nonatomic, retain) TerminalFileDownload *download;
@property(nonatomic, retain) TerminalFileUpload *upload;

// Time since reference date when last output was received. New output in a brief period after the
// session is resized is ignored to avoid making the spinner spin due to resizing.
@property(nonatomic) NSTimeInterval lastOutputIgnoringOutputAfterResizing;

// Time the window was last resized at.
@property(nonatomic) NSTimeInterval lastResize;
@property(atomic, assign) PTYSessionTmuxMode tmuxMode;
@property(nonatomic, readonly) NSString *lastDirectory;
@property(nonatomic, readonly) NSString *lastLocalDirectory;
@property(nonatomic, readonly) BOOL lastLocalDirectoryWasPushed;  // was lastLocalDirectory from shell integration?
@property(nonatomic, readonly) id<VT100RemoteHostReading> lastRemoteHost;  // last remote host at time of setting current directory
@property(nonatomic, strong) iTermSessionDirectoryTracker *directoryTracker;
@property(nonatomic, retain) NSColor *cursorGuideColor;
@property(nonatomic, assign) BOOL useActivePaneBorder;
@property(nonatomic, retain) NSColor *activePaneBorderColor;
@property(nonatomic, copy) NSString *badgeFormat;

// Info about what happens when the program is run so it can be restarted after
// a broken pipe if the user so chooses. Contains $$MACROS$$ pre-substitution.
@property(nonatomic, copy) NSString *program;
@property(nonatomic, copy) NSString *customShell;
@property(nonatomic, copy) NSDictionary *environment;
@property(nonatomic, assign) BOOL isUTF8;
@property(nonatomic, copy) NSDictionary *substitutions;
@property(nonatomic, copy) NSString *guid;
@property(nonatomic, retain) iTermPasteHelper *pasteHelper;
@property(nonatomic, copy) NSString *lastCommand;
@property(nonatomic, retain) iTermExpectation *pasteBracketingOopsieExpectation;
// Reference count for pending bracketed paste first-chunk writes. When > 0,
// subsequent writes are queued in _dataQueue to prevent out-of-order delivery.
@property(nonatomic, assign) NSInteger bracketedPastePending;
@property(nonatomic, copy) NSString *cookie;
@property(nonatomic, strong) NSDate *lastNonFocusReportingWrite;
@property(nonatomic, strong) NSDate *lastFocusReportDate;
@property(nonatomic) NSStringEncoding encoding;

- (void)queueAnnouncement:(iTermAnnouncementViewController *)announcement
               identifier:(NSString *)identifier;
- (void)removeAnnouncementWithIdentifier:(NSString *)identifier;
- (BOOL)haveAutoComposer;
- (void)sendDataQueue;
- (void)bracketedPasteDidExpect;

@end
