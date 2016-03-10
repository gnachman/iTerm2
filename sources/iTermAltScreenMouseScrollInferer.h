//
//  iTermAltScreenMouseScrollInferer.h
//  iTerm2
//
//  Created by George Nachman on 3/9/16.
//
//

#import <Cocoa/Cocoa.h>

@protocol iTermAltScreenMouseScrollInfererDelegate <NSObject>

- (void)altScreenMouseScrollInfererDidInferScrollingIntent:(BOOL)isTrying;

@end

// Tries to guess when the user is frustratedly scrolling with the mouse wheel in alternate
// screen mode.
@interface iTermAltScreenMouseScrollInferer : NSObject

@property(nonatomic, assign) id<iTermAltScreenMouseScrollInfererDelegate> delegate;

- (void)firstResponderDidChange;
- (void)keyDown:(NSEvent *)event;
- (void)nonScrollWheelEvent:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;

@end
