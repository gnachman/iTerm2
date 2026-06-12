//
//  iTermCachingFileManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "iTermCachingFileManager.h"

#import "NSDate+iTerm.h"

@interface iTermCachingFileManagerEntry : NSObject
@property (nonatomic) BOOL exists;
@property (nonatomic) NSTimeInterval expiration;
@property (nonatomic, readonly) BOOL isValid;

+ (instancetype)entryWithExists:(BOOL)exists;

@end

@implementation iTermCachingFileManagerEntry

+ (instancetype)entryWithExists:(BOOL)exists {
    iTermCachingFileManagerEntry *entry = [[iTermCachingFileManagerEntry alloc] init];
    entry.exists = exists;
    const NSTimeInterval TTL = 10;
    entry.expiration = [NSDate it_timeSinceBoot] + TTL;
    return entry;
}

- (BOOL)isValid {
    return [NSDate it_timeSinceBoot] < self.expiration;
}

@end

@implementation iTermCachingFileManager {
    NSCache<NSString *, iTermCachingFileManagerEntry *> *_cache;
}

+ (instancetype)cachingFileManager {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 1000;
    }
    return self;
}

- (BOOL)fileExistsAtPath:(NSString *)path {
    iTermCachingFileManagerEntry *entry = [_cache objectForKey:path];
    if (entry.isValid) {
        return entry.exists;
    }

    const BOOL exists = [super fileExistsAtPath:path];
    entry = [iTermCachingFileManagerEntry entryWithExists:exists];
    
    [_cache setObject:entry forKey:path];
    
    return exists;
}

@end
