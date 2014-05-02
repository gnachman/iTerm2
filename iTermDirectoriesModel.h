//
//  iTermDirectoriesModel.h
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import <Foundation/Foundation.h>

@class VT100RemoteHost;

extern NSString *const kDirectoriesDidChangeNotificationName;

@interface iTermDirectoryEntry : NSObject

@property(nonatomic, copy) NSString *path;
@property(nonatomic, assign) int useCount;
@property(nonatomic, copy) NSDate *lastUse;
@property(nonatomic, copy) NSString *description;
@property(nonatomic, assign) BOOL starred;
@property(nonatomic, copy) NSString *shortcut;

+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary;

@end

// Stores and provides access to recently used and favorited directories per host.
@interface iTermDirectoriesModel : NSObject

+ (instancetype)sharedInstance;

- (void)recordUseOfPath:(NSString *)path
                 onHost:(VT100RemoteHost *)host
               isChange:(BOOL)isChange;

- (NSArray *)entriesSortedByScoreOnHost:(VT100RemoteHost *)host;
- (void)eraseHistory;
- (void)save;

@end
