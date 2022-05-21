//
//  iTermGraphicSource.h
//  iTerm2
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

@class NSColor;
@protocol ProcessInfoProvider;

NS_ASSUME_NONNULL_BEGIN

@interface iTermGraphicSource : NSObject
@property (nonatomic, readonly) NSImage *image;
@property (nonatomic) BOOL disableTinting;

- (BOOL)updateImageForProcessID:(pid_t)pid
                        enabled:(BOOL)enabled
            processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider;

- (BOOL)updateImageForJobName:(NSString *)name enabled:(BOOL)enabled;
- (NSImage * _Nullable)imageForJobName:(NSString *)command;

@end

NS_ASSUME_NONNULL_END
