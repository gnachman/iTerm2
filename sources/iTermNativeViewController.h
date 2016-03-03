//
//  iTermNativeViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/2/16.
//
//

#import "iTermWeakReference.h"
#import <Cocoa/Cocoa.h>

@class iTermNativeViewController;

// iTerm2 implements this delegate method.
@protocol iTermNativeViewControllerDelegate<iTermWeaklyReferenceable>

- (void)nativeViewControllerViewDidLoad:(iTermNativeViewController *)nativeViewController;

// Should figure out a nearby size that is a multiple of line height and not taller than the
// session, tell the terminal app via escape sequence, wait for a response, and then call setSize:
// with the accepted size. Obvs this will done be asynchronously.
- (void)nativeViewController:(iTermNativeViewController *)nativeViewController
                willResizeTo:(NSSize)proposedSize;

@end

// This is the glue code that contains a native view.
@interface iTermNativeViewController : NSViewController<iTermWeaklyReferenceable>

@property(nonatomic, readonly) CGFloat desiredHeight;
@property(nonatomic, retain) id<iTermNativeViewControllerDelegate> nativeViewControllerDelegate;
@property(nonatomic, readonly) NSString *identifier;

// Used to remember the proposed height while waiting for an async response.
@property(nonatomic, assign) NSInteger proposedRows;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

- (void)notifyViewReadyForDisplay;

// The native view may invoke this to request a size change. iTerm2 may also invoke this (e.g.,
// if the window resizes, or the terminal app decides it wants a resize). At some point in the
// future the view will get resized.
- (void)requestSizeChangeTo:(NSSize)desiredSize;

@end

@interface iTermNativeViewController(Internal)
// Forces an immediate size change. Not to be called by native views; only for iTerm2.
- (void)setSize:(NSSize)size;
@end
