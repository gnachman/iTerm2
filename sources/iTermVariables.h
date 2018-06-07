//
//  iTermVariables.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

extern NSString *const iTermVariableKeyApplicationPID;
extern NSString *const iTermVariableKeySessionAutoLogID;
extern NSString *const iTermVariableKeySessionColumns;
extern NSString *const iTermVariableKeySessionCreationTimeString;
extern NSString *const iTermVariableKeySessionHostname;
extern NSString *const iTermVariableKeySessionID;
extern NSString *const iTermVariableKeySessionLastCommand;
extern NSString *const iTermVariableKeySessionPath;
extern NSString *const iTermVariableKeySessionName;
extern NSString *const iTermVariableKeySessionRows;
extern NSString *const iTermVariableKeySessionTTY;
extern NSString *const iTermVariableKeySessionUsername;
extern NSString *const iTermVariableKeyTermID;

extern NSString *const iTermVariableKeySessionProfileName;
extern NSString *const iTermVariableKeySessionIconName;
extern NSString *const iTermVariableKeySessionWindowName;
extern NSString *const iTermVariableKeySessionJob;

// Returns an array of all known variables.
NSArray<NSString *> *iTermVariablesGetAll(void);

// Register a new path as having been seen.
void iTermVariablesAdd(NSString *variable);
