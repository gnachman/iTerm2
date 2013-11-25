//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>
// This is for the args to CGSSetWindowBackgroundBlurRadiusFunction, which is used for window-blurring using undocumented APIs.
#import "CGSInternal.h"



extern const int FutureNSWindowCollectionBehaviorStationary;

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
- (BOOL)performSelectorReturningCGFloat:(SEL)selector withObjects:(NSArray *)objects;
@end

@interface NSScroller (future)
- (void)futureSetKnobStyle:(NSInteger)newKnobStyle;
@end

typedef CGError CGSSetWindowBackgroundBlurRadiusFunction(CGSConnectionID cid, CGSWindowID wid, NSUInteger blur);
CGSSetWindowBackgroundBlurRadiusFunction* GetCGSSetWindowBackgroundBlurRadiusFunction(void);

// 10.7-only function.
typedef void CTFontDrawGlyphsFunction(CTFontRef runFont, const CGGlyph *glyphs, NSPoint *positions, int glyphCount, CGContextRef ctx);
CTFontDrawGlyphsFunction* GetCTFontDrawGlyphsFunction(void);

@interface NSScreen (future)
- (CGFloat)futureBackingScaleFactor;
@end

