//
//  iTermGraphicsUtilities.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/10/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

int iTermSetSmoothing(CGContextRef ctx,
                      int * _Nullable savedFontSmoothingStyle,
                      BOOL useThinStrokes,
                      BOOL antialiased);

NS_ASSUME_NONNULL_END
