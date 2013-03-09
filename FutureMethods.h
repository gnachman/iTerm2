//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>

#ifdef BLOCKS_NOT_AVAILABLE
// OS 10.5 Compatibility

@protocol NSControlTextEditingDelegate
@end

@protocol NSMenuDelegate
@end

@protocol NSNetServiceBrowserDelegate
@end

@protocol NSNetServiceDelegate
@end

@protocol NSSplitViewDelegate
@end

@protocol NSTableViewDataSource
@end

@protocol NSTableViewDelegate
@end

@protocol NSTextFieldDelegate
@end

@protocol NSTextViewDelegate
@end

@protocol NSTokenFieldDelegate
@end

@protocol NSToolbarDelegate
@end

@protocol NSWindowDelegate
@end

#endif

extern const int FutureNSWindowCollectionBehaviorStationary;

@interface NSView (Future)
- (void)futureSetAcceptsTouchEvents:(BOOL)value;
- (void)futureSetWantsRestingTouches:(BOOL)value;
@end

@interface NSEvent (Future)
- (NSArray *)futureTouchesMatchingPhase:(int)phase inView:(NSView *)view;
@end

@interface NSWindow (Future)
- (void)futureSetRestorable:(BOOL)value;
- (void)futureSetRestorationClass:(Class)class;
- (void)futureInvalidateRestorableState;
@end

enum {
    FutureNSScrollerStyleLegacy       = 0,
    FutureNSScrollerStyleOverlay      = 1
};
typedef NSInteger FutureNSScrollerStyle;

@interface NSScroller (Future)
- (FutureNSScrollerStyle)futureScrollerStyle;
@end

@interface NSScrollView (Future)
- (FutureNSScrollerStyle)futureScrollerStyle;
@end

@interface CIImage (Future)
@end

@interface NSObject (Future)
- (BOOL)performSelectorReturningBool:(SEL)selector withObjects:(NSArray *)objects;
@end

@interface NSScroller (future)
- (void)futureSetKnobStyle:(NSInteger)newKnobStyle;
@end
