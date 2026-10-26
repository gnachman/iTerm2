//
//  iTermJobTreeViewController.h
//  iTerm2
//
//  Created by George Nachman on 1/18/19.
//

#import <Cocoa/Cocoa.h>

@protocol ProcessInfoProvider;

NS_ASSUME_NONNULL_BEGIN

@interface iTermJobTreeViewController : NSViewController
@property (nonatomic) pid_t pid;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic) BOOL animateChanges;
@property (nonatomic) BOOL useGlassEffectView;
@property (nonatomic) id<ProcessInfoProvider> processInfoProvider;

// Called before each periodic refresh, so a host whose session's root pid or process info provider
// can change without telling it (e.g. a tmux pane on an SSH Integration host, whose provider
// appears once the connection is framing) can set them again. Setting unchanged values does
// nothing.
@property (nonatomic, copy, nullable) void (^willRefresh)(iTermJobTreeViewController *controller);

// Height of the bottom strip that holds the signal picker and kill button. The
// outline scroll view occupies everything above it. Space-constrained hosts
// (e.g. the toolbelt) may reduce this. Defaults to 38.
@property (nonatomic) CGFloat toolbarHeight;

// Distance from the bottom of the view to the bottom of the signal picker /
// kill button. Combined with toolbarHeight this controls the margin above and
// below the controls. Defaults to 8 (centers the 22pt controls in the default
// 38pt strip).
@property (nonatomic) CGFloat controlsBottomMargin;

// Whether to install a background visual effect view behind the job tree.
// Hosts that already provide their own background (e.g. the toolbelt) can set
// this to NO. Defaults to YES. Must be set before the view is loaded.
@property (nonatomic) BOOL useVisualEffectView;

- (instancetype)initWithProcessID:(pid_t)pid
              processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (void)setFont:(NSFont *)font;
- (void)sizeOutlineViewToFit;

@end

NS_ASSUME_NONNULL_END
