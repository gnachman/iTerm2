//
//  iTermVariables.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import "iTermVariables.h"

NSString *const iTermVariableKeyApplicationPID = @"iterm2.pid";
NSString *const iTermVariableKeySessionAutoLogID = @"session.autoLogId";
NSString *const iTermVariableKeySessionColumns = @"session.columns";
NSString *const iTermVariableKeySessionCreationTimeString = @"session.creationTimeString";
NSString *const iTermVariableKeySessionHostname = @"session.hostname";
NSString *const iTermVariableKeySessionID = @"session.id";
NSString *const iTermVariableKeySessionLastCommand = @"session.lastCommand";
NSString *const iTermVariableKeySessionPath = @"session.path";
NSString *const iTermVariableKeySessionName = @"session.name";
NSString *const iTermVariableKeySessionRows = @"session.rows";
NSString *const iTermVariableKeySessionTTY = @"session.tty";
NSString *const iTermVariableKeySessionUsername = @"session.username";
NSString *const iTermVariableKeyTermID = @"session.termid";

static NSMutableSet<NSString *> *iTermVariablesGetMutableSet() {
    static NSMutableSet<NSString *> *userDefined;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *systemDefined =
            @[ iTermVariableKeyApplicationPID,
               iTermVariableKeySessionAutoLogID,
               iTermVariableKeySessionColumns,
               iTermVariableKeySessionCreationTimeString,
               iTermVariableKeySessionHostname,
               iTermVariableKeySessionID,
               iTermVariableKeySessionLastCommand,
               iTermVariableKeySessionPath,
               iTermVariableKeySessionName,
               iTermVariableKeySessionRows,
               iTermVariableKeySessionTTY,
               iTermVariableKeySessionUsername,
               iTermVariableKeyTermID ];
        userDefined = [NSMutableSet setWithArray:systemDefined];
    });
    return userDefined;
}

NSArray<NSString *> *iTermVariablesGetAll(void) {
    return [iTermVariablesGetMutableSet() allObjects];
}

void iTermVariablesAdd(NSString *variable) {
    [iTermVariablesGetMutableSet() addObject:variable];
}

