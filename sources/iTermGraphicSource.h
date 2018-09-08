//
//  iTermGraphicSource.h
//  iTerm2
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermGraphicSource : NSObject

- (NSImage *)imageForSessionWithProcessID:(pid_t)pid;

@end

NS_ASSUME_NONNULL_END
