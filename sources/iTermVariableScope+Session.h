//
//  iTermVariableScope+Session.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermTabScope;
@class iTermVariables;

@protocol iTermSessionScope<NSObject>

@property (nullable, nonatomic, strong) NSString *autoLogId;
@property (nullable, nonatomic, strong) NSNumber *columns;
@property (nullable, nonatomic, strong) NSString *creationTimeString;
@property (nullable, nonatomic, strong) NSString *hostname;
@property (nullable, nonatomic, strong) NSString *ID;
@property (nullable, nonatomic, strong) NSString *lastCommand;
@property (nullable, nonatomic, strong) NSString *path;
@property (nullable, nonatomic, strong) NSString *name;
@property (nullable, nonatomic, strong) NSNumber *rows;
@property (nullable, nonatomic, strong) NSString *tty;
@property (nullable, nonatomic, strong) NSString *username;
@property (nullable, nonatomic, strong) NSString *termid;
@property (nullable, nonatomic, strong) NSString *profileName;
@property (nullable, nonatomic, strong) NSString *terminalIconName;
@property (nullable, nonatomic, strong) NSString *triggerName;
@property (nullable, nonatomic, strong) NSString *windowName;
@property (nullable, nonatomic, strong) NSString *jobName;
@property (nullable, nonatomic, strong) NSString *commandLine;
@property (nullable, nonatomic, strong) NSString *presentationName;
@property (nullable, nonatomic, strong) NSString *tmuxRole;
@property (nullable, nonatomic, strong) NSString *tmuxClientName;
@property (nullable, nonatomic, strong) NSString *autoNameFormat;
@property (nullable, nonatomic, strong) NSString *autoName;
@property (nullable, nonatomic, strong) NSNumber *tmuxWindowPane;
@property (nullable, nonatomic, strong) NSNumber *jobPid;
@property (nullable, nonatomic, strong) NSNumber *pid;
@property (nullable, nonatomic, strong) NSString *tmuxPaneTitle;
@property (nullable, nonatomic, strong) NSString *tmuxStatusLeft;
@property (nullable, nonatomic, strong) NSString *tmuxStatusRight;
@property (nullable, nonatomic, strong) NSNumber *mouseReportingMode;
@property (nullable, nonatomic, strong) NSString *badge;
@property (nullable, nonatomic, readonly) iTermVariableScope<iTermTabScope> *tab;

@end

@interface iTermVariableScope (Session)<iTermSessionScope>

+ (instancetype)newSessionScopeWithVariables:(iTermVariables *)variables;

@end


NS_ASSUME_NONNULL_END
