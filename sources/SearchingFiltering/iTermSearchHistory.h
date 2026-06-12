//
//  iTermSearchHistory.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermSearchHistory : NSObject
@property (nonatomic, readonly) NSArray<NSString *> *queries;
@property (nonatomic) NSInteger maximumCount;

+ (instancetype)sharedInstance;
- (void)addQuery:(NSString *)query;
- (void)eraseHistory;
- (void)coalescingFence;

@end

NS_ASSUME_NONNULL_END
