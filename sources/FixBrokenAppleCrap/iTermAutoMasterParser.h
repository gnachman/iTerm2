//
//  iTermAutoMasterParser.h
//  iTerm2
//
//  Created by George Nachman on 3/22/16.
//
//

#import <Foundation/Foundation.h>

// Parses /etc/auto_master. Allows you to query the maps to be mounted only (not lines that start
// with + or other kinds of lines).
@interface iTermAutoMasterParser : NSObject

+ (instancetype)sharedInstance;

// Returns all auto_master mountpoints. This is a conservative guess at what might be an nfs mount.
- (NSArray<NSString *> *)mountpoints;

@end
