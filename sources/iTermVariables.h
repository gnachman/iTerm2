//
//  iTermVariables.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

#import "iTermVariableHistory.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermVariableKeyGlobalScopeName;

extern NSString *const iTermVariableKeyApplicationPID;
extern NSString *const iTermVariableKeyApplicationLocalhostName;
extern NSString *const iTermVariableKeyApplicationEffectiveTheme;

extern NSString *const iTermVariableKeyTabTitleOverride;
extern NSString *const iTermVariableKeyTabTitleOverrideFormat;
extern NSString *const iTermVariableKeyTabCurrentSession;
extern NSString *const iTermVariableKeyTabID;
extern NSString *const iTermVariableKeyTabTmuxWindowTitle;  // #{T:set-titles-string} for a particular tmux window
extern NSString *const iTermVariableKeyTabTmuxWindowName;
extern NSString *const iTermVariableKeyTabWindow;
extern NSString *const iTermVariableKeyTabTitle;

// If this window is a tmux client, this is the window number defined by
// the tmux server. -1 if not a tmux client.
extern NSString *const iTermVariableKeyTabTmuxWindow;

extern NSString *const iTermVariableKeySessionAutoLogID;
extern NSString *const iTermVariableKeySessionColumns;
extern NSString *const iTermVariableKeySessionCreationTimeString;
extern NSString *const iTermVariableKeySessionHostname;
extern NSString *const iTermVariableKeySessionID;
extern NSString *const iTermVariableKeySessionLastCommand;
extern NSString *const iTermVariableKeySessionPath;
extern NSString *const iTermVariableKeySessionName;  // Registers the computed title
extern NSString *const iTermVariableKeySessionRows;
extern NSString *const iTermVariableKeySessionTTY;
extern NSString *const iTermVariableKeySessionUsername;
extern NSString *const iTermVariableKeySessionTermID;
extern NSString *const iTermVariableKeySessionProfileName;  // current profile name
extern NSString *const iTermVariableKeySessionAutoNameFormat;  // Defaults to profile name. Then, most recent of manually set or icon name. Is an interpolated string.
extern NSString *const iTermVariableKeySessionAutoName;  // Evaluated value of autoNameFormat
extern NSString *const iTermVariableKeySessionIconName;  // set by esc code
extern NSString *const iTermVariableKeySessionTriggerName;
extern NSString *const iTermVariableKeySessionWindowName;  // set by esc code
extern NSString *const iTermVariableKeySessionJob;  // job name, not affected by modifying argv[0]
extern NSString *const iTermVariableKeySessionProcessTitle;  // process title, affected by modifying argv[0]. see issue 4214 for details.
extern NSString *const iTermVariableKeySessionCommandLine;  // Current foreground job with arguments
extern NSString *const iTermVariableKeySessionPresentationName;  // What's shown in the session title view
extern NSString *const iTermVariableKeySessionTmuxPaneTitle;  // #{pane_title} for a particular session
extern NSString *const iTermVariableKeySessionTmuxRole;  // Unset (normal session), "gateway" (where you ran tmux -CC), or "client".
extern NSString *const iTermVariableKeySessionTmuxClientName;  // Set on tmux gateways. Gives a name for the tmux session.
extern NSString *const iTermVariableKeySessionTmuxWindowPane;  // NSNumber. Window pane number #{pane_id}. Set if the session is a tmux session;
extern NSString *const iTermVariableKeySessionTmuxWindowPaneIndex;  // NSString. #{pane_index} for a particular session. Only available on tmux 3.2+.
extern NSString *const iTermVariableKeySessionJobPid;  // NSNumber. Process id of foreground job.
extern NSString *const iTermVariableKeySessionChildPid;  // NSNumber. Process id of child of session task.
extern NSString *const iTermVariableKeySessionEffectiveSessionRootPid;  // NSNumber. Process id of child of session task or of ssh.
extern NSString *const iTermVariableKeySessionTmuxStatusLeft;  // String. Only set when in tmux integration mode.
extern NSString *const iTermVariableKeySessionTmuxStatusRight;  // String. Only set when in tmux integration mode.
extern NSString *const iTermVariableKeySessionMouseReportingMode;  // NSNumber (MouseMode)
extern NSString *const iTermVariableKeySessionShowingAlternateScreen;  // NSBoolean
extern NSString *const iTermVariableKeySessionBadge;  // NSString. Evaluated badge swifty string.
extern NSString *const iTermVariableKeySessionTab;  // NString. Containing tab.
extern NSString *const iTermVariableKeySessionSelection;  // NSString. Containing selected text.
extern NSString *const iTermVariableKeySessionSelectionLength;  // NSNumber. Contains length of selected text.
extern NSString *const iTermVariableKeySessionParent;  // Session that was active when this one was created, if any.
extern NSString *const iTermVariableKeySessionBellCount;  // NSNumber. Number of times the bell has tried to ring.
extern NSString *const iTermVariableKeySessionLogFilename;  // NSString. Path to log file. Unset if not logging.
extern NSString *const iTermVariableKeySessionMouseInfo;  // [x=NSNumber, y=NSNumber, button=NSNumber, count=NSNumber, modifiers=NSNumber, sideEffects=NSNumber, state=NSNumber]. Info about last lcick.
extern NSString *const iTermVariableKeySessionApplicationKeypad;  // NSNumber. Boolean - in application keypad mode?
extern NSString *const iTermVariableKeySessionHomeDirectory;  // NSString. Value of $HOME, including remote host when ssh integration+framer used.
extern NSString *const iTermVariableKeySSHIntegrationLevel;  // NSNumber. 0=none, 1=basic, 2=framer
extern NSString *const iTermVariableKeyShell;  // NSString. Value of last path component of $SHELL
extern NSString *const iTermVariableKeyUname;  // NSString. Value of uname -a

extern NSString *const iTermVariableKeyWindowTitleOverrideFormat;
extern NSString *const iTermVariableKeyWindowCurrentTab;
extern NSString *const iTermVariableKeyWindowTitleOverride;
extern NSString *const iTermVariableKeyWindowID;
extern NSString *const iTermVariableKeyWindowFrame;
extern NSString *const iTermVariableKeyWindowStyle;
extern NSString *const iTermVariableKeyWindowNumber;
extern NSString *const iTermVariableKeyWindowIsHotkeyWindow;

@protocol iTermObject;
@class iTermVariables;

@protocol iTermVariableReference<NSObject>

@property (nullable, nonatomic, copy) void (^onChangeBlock)(void);
@property (nonatomic, readonly) NSString *path;
@property (nullable, nonatomic, strong) id value;

- (void)addLinkToVariables:(iTermVariables *)variables localPath:(NSString *)path;
- (void)invalidate;
- (void)valueDidChange;
- (void)removeAllLinks;

@end

@protocol iTermVariableVendor<NSObject>
- (void)addLinksToReference:(id<iTermVariableReference>)reference;
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name;
- (nullable id)valueForVariableName:(NSString *)name;
@end

// Typically you would not use this directly. Create one and bind it to a
// scope, then perform references to it from the scope.
@interface iTermVariables : NSObject<iTermVariableVendor>

@property (nonatomic, readonly, weak) id<iTermObject> owner;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSDictionary *encodableDictionaryValue;
@property (nonatomic, readonly) NSDictionary<NSString *,NSString *> *stringValuedDictionary;
@property (nonatomic, readonly) NSArray<NSString *> *allNames;
@property (nonatomic, readonly) NSString *debugInfo;

// If you set this then the frame can be searched globally.
@property (nonatomic, nullable, copy) NSString *primaryKey;

+ (instancetype)globalInstance;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context
                          owner:(id<iTermObject>)owner NS_DESIGNATED_INITIALIZER;

// WARNING: You almost never want to use this. It is useful if you need to get a known child out, as
// open quickly does to find the names of all user variables.
- (nullable id)discouragedValueForVariableName:(NSString *)name;

// Don't use this unless you really know what you're doing.
- (nullable id)rawValueForVariableName:(NSString *)name;

- (void)removeLinkToReference:(id<iTermVariableReference>)reference
                         path:(NSString *)path;

@end


NS_ASSUME_NONNULL_END
