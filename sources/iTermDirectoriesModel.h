//
//  iTermDirectoriesModel.h
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import <Cocoa/Cocoa.h>

@class VT100RemoteHost;

extern NSString *const kDirectoriesDidChangeNotificationName;

@interface iTermDirectoryEntry : NSObject

@property(nonatomic, copy) NSString *path;
@property(nonatomic, assign) int useCount;
@property(nonatomic, copy) NSDate *lastUse;
@property(nonatomic, assign) BOOL starred;
@property(nonatomic, copy) NSString *shortcut;

+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary;
- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn;

// Take an attributedString having |path| with extra styles and remove bits from it to fit.
- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn
                               basedOnAttributedString:(NSAttributedString *)attributedString
                                        baseAttributes:(NSDictionary *)baseAttributes;

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
- (BOOL)haveEntriesForHost:(VT100RemoteHost *)host;

#pragma mark - Testing

- (void)eraseHistoryForHost:(VT100RemoteHost *)host;

@end
