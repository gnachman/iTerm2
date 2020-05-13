//
//  iTermTmuxWindowCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermTmuxWindowCacheDidChange;

@interface iTermTmuxWindowCacheWindowInfo: NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) int windowNumber;
@property (nonatomic, readonly) int sessionNumber;
@property (nonatomic, readonly) NSString *clientName;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermTmuxWindowCache : NSObject
@property (nonatomic, readonly) NSArray<iTermTmuxWindowCacheWindowInfo *> *hiddenWindows;

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
