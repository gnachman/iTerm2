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

// Returns mountpoints having a given map.
- (NSArray<NSString *> *)mountpointsWithMap:(NSString *)map;

@end
