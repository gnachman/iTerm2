//
//  iTermSoundPlayer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/6/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermSoundPlayer : NSObject

+ (instancetype)keyClick;
- (void)play;

@end

NS_ASSUME_NONNULL_END
