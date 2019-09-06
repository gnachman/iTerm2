//
//  iTermOpenDirectory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/5/19.
//

#import "iTermOpenDirectory.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

#import <OpenDirectory/OpenDirectory.h>

@implementation iTermOpenDirectory

// This is (I hope) the equivalent of the command "dscl . read /Users/$USER UserShell", which
// appears to be how you get the user's shell nowadays. Returns nil if it can't be gotten.
+ (NSString *)userShell {
    if (![iTermAdvancedSettingsModel useOpenDirectory]) {
        return nil;
    }

    DLog(@"Trying to figure out the user's shell.");
    NSError *error = nil;
    ODNode *node = [ODNode nodeWithSession:[ODSession defaultSession]
                                      type:kODNodeTypeLocalNodes
                                     error:&error];
    if (!node) {
        DLog(@"Failed to get node for default session: %@", error);
        return nil;
    }
    ODQuery *query = [ODQuery queryWithNode:node
                             forRecordTypes:kODRecordTypeUsers
                                  attribute:kODAttributeTypeRecordName
                                  matchType:kODMatchEqualTo
                                queryValues:NSUserName()
                           returnAttributes:kODAttributeTypeStandardOnly
                             maximumResults:0
                                      error:&error];
    if (!query) {
        DLog(@"Failed to query for record matching user name: %@", error);
        return nil;
    }
    DLog(@"Performing synchronous request.");
    NSArray *result = [query resultsAllowingPartial:NO error:nil];
    DLog(@"Got %lu results", (unsigned long)result.count);
    ODRecord *record = [result firstObject];
    DLog(@"Record is %@", record);
    NSArray *shells = [record valuesForAttribute:kODAttributeTypeUserShell error:&error];
    if (!shells) {
        DLog(@"Error getting shells: %@", error);
        return nil;
    }
    DLog(@"Result has these shells: %@", shells);
    NSString *shell = [shells firstObject];
    DLog(@"Returning %@", shell);
    return shell;
}


@end
