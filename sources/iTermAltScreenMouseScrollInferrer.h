//
//  iTermAltScreenMouseScrollInferrer.h
//  iTerm2
//
//  Created by George Nachman on 3/9/16.
//
//

#import <Cocoa/Cocoa.h>

@protocol iTermAltScreenMouseScrollInferrerDelegate <NSObject>

- (void)altScreenMouseScrollInferrerDidInferScrollingIntent:(BOOL)isTrying;

@end

// Tries to guess when the user is frustratingly scrolling with the mouse wheel in alternate
// screen mode.
@interface iTermAltScreenMouseScrollInferrer : NSObject

@property(nonatomic, assign) id<iTermAltScreenMouseScrollInferrerDelegate> delegate;

- (void)firstResponderDidChange;
- (void)keyDown:(NSEvent *)event;
- (void)nonScrollWheelEvent:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;

@end
