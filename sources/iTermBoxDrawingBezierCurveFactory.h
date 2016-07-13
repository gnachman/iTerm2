//
//  iTermBoxDrawingBezierCurveFactory.h
//  iTerm2
//
//  Created by George Nachman on 7/15/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermBoxDrawingBezierCurveFactory : NSObject

+ (NSCharacterSet *)boxDrawingCharactersWithBezierPaths;
+ (NSArray<NSBezierPath *> *)bezierPathsForBoxDrawingCode:(unichar)code
                                                 cellSize:(NSSize)cellSize;

@end
