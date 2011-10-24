//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>

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