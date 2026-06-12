//
//  iTermCachingFileManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCachingFileManager : NSFileManager

+ (instancetype)cachingFileManager;

@end

NS_ASSUME_NONNULL_END
