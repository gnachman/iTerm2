//
//  iTermVariables.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermVariableKeyGlobalScopeName;

extern NSString *const iTermVariableKeyApplicationPID;

extern NSString *const iTermVariableKeyTabTitleOverride;
extern NSString *const iTermVariableKeyTabCurrentSession;

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
extern NSString *const iTermVariableKeySessionAutoName;  // Defaults to profile name. Then, most recent of manually set or icon name.
extern NSString *const iTermVariableKeySessionIconName;  // set by esc code
extern NSString *const iTermVariableKeySessionTriggerName;
extern NSString *const iTermVariableKeySessionWindowName;  // set by esc code
extern NSString *const iTermVariableKeySessionJob;
extern NSString *const iTermVariableKeySessionPresentationName;  // What's shown in the session title view
extern NSString *const iTermVariableKeySessionTmuxWindowTitle;  // All tmux window panes share the same window title
extern NSString *const iTermVariableKeySessionTmuxRole;  // Unset (normal session), "gateway" (where you ran tmux -CC), or "client".
extern NSString *const iTermVariableKeySessionTmuxClientName;  // Set on tmux gateways. Gives a name for the tmux session.
extern NSString *const iTermVariableKeySessionTmuxWindowPane;  // NSNumber. Window pane number. Set if the session is a tmux session;
extern NSString *const iTermVariableKeySessionJobPid;  // NSNumber. Process id of foreground job.
extern NSString *const iTermVariableKeySessionChildPid;  // NSNumber. Process id of child of session task.
extern NSString *const iTermVariableKeySessionTmuxStatusLeft;  // String. Only set when in tmux integration mode.
extern NSString *const iTermVariableKeySessionTmuxStatusRight;  // String. Only set when in tmux integration mode.

extern NSString *const iTermVariableKeyWindowTitleOverride;
extern NSString *const iTermVariableKeyWindowCurrentTab;

@class iTermVariables;
@class iTermVariableScope;

typedef NS_OPTIONS(NSUInteger, iTermVariablesSuggestionContext) {
    iTermVariablesSuggestionContextNone = 0,
    iTermVariablesSuggestionContextSession = (1 << 0),
    iTermVariablesSuggestionContextTab = (1 << 1),
    iTermVariablesSuggestionContextApp = (1 << 2),
    iTermVariablesSuggestionContextWindow = (1 << 4),
};

@protocol iTermVariablesDelegate<NSObject>
- (void)variables:(iTermVariables *)variables didChangeValuesForNames:(NSSet<NSString *> *)changedNames group:(dispatch_group_t)group;
@end

// Usage:
// iTermVariables *child = [[iTermVariables alloc] initWithContext:(iTermVariablesSuggestionContext)context];
// [child setValuesFromDictionary:dict];
// child.delegate = self;
// [parent setValue:child forVariableNamed:@"child name"];
@interface iTermVariables : NSObject

@property (nonatomic, weak) id<iTermVariablesDelegate> delegate;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSDictionary<NSString *,NSString *> *stringValuedDictionary;

+ (instancetype)globalInstance;

+ (void)recordUseOfVariableNamed:(NSString *)name
                       inContext:(iTermVariablesSuggestionContext)context;
+ (NSSet<NSString *> *)recordedVariableNamesInContext:(iTermVariablesSuggestionContext)context;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context NS_DESIGNATED_INITIALIZER;

// WARNING: You almost never want to use this. It is useful if you need to get a known child out, as
// open quickly does to find the names of all user variables.
- (id)discouragedValueForVariableName:(NSString *)name;

@end

// Represents the variables that are visible from a particular callsite. Each
// set of variables except one (that of the most local scope) must have a name.
// Variables are searched for one matching the name.
@interface iTermVariableScope : NSObject
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *dictionaryWithStringValues;
@property (nonatomic, readonly) id (^functionCallSource)(NSString *);

+ (instancetype)globalsScope;

- (void)addVariables:(iTermVariables *)variables toScopeNamed:(nullable NSString *)scopeName;
- (id)valueForVariableName:(NSString *)name;
- (NSString *)stringValueForVariableName:(NSString *)name;
// Values of NSNull get unset
- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict;

// nil or NSNull value means unset it.
// Returns whether it was set. If the value is unchanged, it does not get set.
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name;

// Freaking KVO crap keeps autocompleting and causing havoc
- (void)setValue:(nullable id)value forKey:(NSString *)key NS_UNAVAILABLE;
- (void)setValuesForKeysWithDictionary:(NSDictionary<NSString *, id> *)keyedValues NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
