//
//  iTermHotKeyMigrationHelper.h
//  iTerm2
//
//  Created by George Nachman on 6/24/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermHotKeyMigrationHelper : NSObject

@property(nonatomic, readonly) BOOL didMigration;

+ (instancetype)sharedInstance;
- (void)migrateSingleHotkeyToMulti;

@end
