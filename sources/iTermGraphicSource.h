//
//  iTermGraphicSource.h
//  iTerm2
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermGraphicSource : NSObject
@property (nonatomic, readonly) NSImage *image;

- (BOOL)updateImageForProcessID:(pid_t)pid enabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
