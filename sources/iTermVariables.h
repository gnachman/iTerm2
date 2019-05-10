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
extern NSString *const iTermVariableKeyTabWindow;

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
extern NSString *const iTermVariableKeySessionJob;
extern NSString *const iTermVariableKeySessionPresentationName;  // What's shown in the session title view
extern NSString *const iTermVariableKeySessionTmuxWindowTitle;  // All tmux window panes share the same window title
extern NSString *const iTermVariableKeySessionTmuxWindowTitleEval;  // Result of evaluating NSString *const iTermVariableKeySessionTmuxWindowTitle
extern NSString *const iTermVariableKeySessionTmuxRole;  // Unset (normal session), "gateway" (where you ran tmux -CC), or "client".
extern NSString *const iTermVariableKeySessionTmuxClientName;  // Set on tmux gateways. Gives a name for the tmux session.
extern NSString *const iTermVariableKeySessionTmuxWindowPane;  // NSNumber. Window pane number. Set if the session is a tmux session;
extern NSString *const iTermVariableKeySessionJobPid;  // NSNumber. Process id of foreground job.
extern NSString *const iTermVariableKeySessionChildPid;  // NSNumber. Process id of child of session task.
extern NSString *const iTermVariableKeySessionTmuxStatusLeft;  // String. Only set when in tmux integration mode.
extern NSString *const iTermVariableKeySessionTmuxStatusRight;  // String. Only set when in tmux integration mode.
extern NSString *const iTermVariableKeySessionMouseReportingMode;  // NSNumber (MouseMode)
extern NSString *const iTermVariableKeySessionBadge;  // NSString. Evaluated badge swifty string.
extern NSString *const iTermVariableKeySessionTab;  // NString. Containing tab.

extern NSString *const iTermVariableKeyWindowTitleOverrideFormat;
extern NSString *const iTermVariableKeyWindowCurrentTab;
extern NSString *const iTermVariableKeyWindowTitleOverride;

@class iTermVariableReference;
@class iTermVariables;
@class iTermVariableScope;

// Typically you would not use this directly. Create one and bind it to a
// scope, then perform references to it from the scope.
@interface iTermVariables : NSObject

@property (nonatomic, readonly, weak) id owner;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSDictionary<NSString *,NSString *> *stringValuedDictionary;
@property (nonatomic, readonly) NSArray<NSString *> *allNames;
@property (nonatomic, readonly) NSString *debugInfo;

+ (instancetype)globalInstance;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context owner:(id)owner NS_DESIGNATED_INITIALIZER;

// WARNING: You almost never want to use this. It is useful if you need to get a known child out, as
// open quickly does to find the names of all user variables.
- (nullable id)discouragedValueForVariableName:(NSString *)name;

// Don't use this unless you really know what you're doing.
- (nullable id)rawValueForVariableName:(NSString *)name;

- (void)removeLinkToReference:(iTermVariableReference *)reference
                         path:(NSString *)path;

@end


NS_ASSUME_NONNULL_END
