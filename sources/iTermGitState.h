//
//  iTermGitState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitState : NSObject<NSCopying>
@property (nonatomic, copy) NSString *xcode;
@property (nonatomic, copy) NSString *pushArrow;
@property (nonatomic, copy) NSString *pullArrow;
@property (nonatomic, copy) NSString *branch;
@property (nonatomic) BOOL dirty;
@end

NS_ASSUME_NONNULL_END
