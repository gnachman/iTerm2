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

// Posted on the main thread after +reloadGraphicMaps changes the color/icon maps, so live sessions
// can recompute their currently-displayed icon instead of waiting for the next foreground-job change.
extern NSString *const iTermGraphicSourceDidReloadNotification;

@interface iTermGraphicSource : NSObject
@property (nonatomic, readonly) NSImage *image;
@property (nonatomic) BOOL disableTinting;

// The icon is chosen from the deepest foreground job actually attached to the
// terminal, rather than a foreground-process-group helper (e.g. an MCP server)
// that happens to be deeper in the tree.
- (BOOL)updateImageForProcessID:(pid_t)pid
                        enabled:(BOOL)enabled
            processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider;

- (BOOL)updateImageForJobName:(NSString *)name enabled:(BOOL)enabled;
- (NSImage * _Nullable)imageForJobName:(NSString *)command;

// Reloads the color/icon customization maps from the bundle and the user's
// graphic_colors.json/graphic_icons.json. Call after those files change on disk (e.g. settings
// sync) so customizations apply without a relaunch.
+ (void)reloadGraphicMaps;

@end

NS_ASSUME_NONNULL_END
