//
//  iTermBoxDrawingBezierCurveFactory.m
//  iTerm2
//
//  Created by George Nachman on 7/15/16.
//
//

#import "iTermBoxDrawingBezierCurveFactory.h"
#import "charmaps.h"
#import "NSArray+iTerm.h"

@implementation iTermBoxDrawingBezierCurveFactory

+ (NSCharacterSet *)boxDrawingCharactersWithBezierPaths {
    static NSCharacterSet *sBoxDrawingCharactersWithBezierPaths;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sBoxDrawingCharactersWithBezierPaths =
            [[NSCharacterSet characterSetWithCharactersInString:@"─━│┃┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤"
              @"┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬╴╵╶╷╸╹╺╻╼╽╾╿"] retain];
    });
    return sBoxDrawingCharactersWithBezierPaths;
}



+ (NSArray<NSBezierPath *> *)bezierPathsForBoxDrawingCode:(unichar)code
                                                 cellSize:(NSSize)cellSize {
    //          l         hc-1    hc-1/2    hc    hc+1/2      hc+1             r
    //          a         b       c         d     e           f                g
    // t        1
    //
    // vc-1     2
    // vc-1/2   3
    // vc       4
    // vc+1/2   5
    // vc+1     6
    //
    // b        7

    NSString *components = nil;
    switch (code) {
        case iTermBoxDrawingCodeLightHorizontal:  // ─
            components = @"a4g4";
            break;
        case iTermBoxDrawingCodeHeavyHorizontal:  // ━
            components = @"a3g3 a5g5";
            break;
        case iTermBoxDrawingCodeLightVertical:  // │
            components = @"d1d7";
            break;
        case iTermBoxDrawingCodeHeavyVertical:  // ┃
            components = @"c1c7 e1e7";
            break;
            
        case iTermBoxDrawingCodeLightTripleDashHorizontal:  // ┄
        case iTermBoxDrawingCodeHeavyTripleDashHorizontal:  // ┅
        case iTermBoxDrawingCodeLightTripleDashVertical:  // ┆
        case iTermBoxDrawingCodeHeavyTripleDashVertical:  // ┇
        case iTermBoxDrawingCodeLightQuadrupleDashHorizontal:  // ┈
        case iTermBoxDrawingCodeHeavyQuadrupleDashHorizontal:  // ┉
        case iTermBoxDrawingCodeLightQuadrupleDashVertical:  // ┊
        case iTermBoxDrawingCodeHeavyQuadrupleDashVertical:  // ┋
            return nil;
            
        case iTermBoxDrawingCodeLightDownAndRight:  // ┌
            components = @"g4d4 d4d7";
            break;
        case iTermBoxDrawingCodeDownLightAndRightHeavy:  // ┍
            components = @"g3d3 d3d7 g5d5";
            break;
        case iTermBoxDrawingCodeDownHeavyAndRightLight:  // ┎
            components = @"g4c4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeHeavyDownAndRight:  // ┏
            components = @"g3c3 c3c7 g5e5 e5e7";
            break;
        case iTermBoxDrawingCodeLightDownAndLeft:  // ┐
            components = @"a4d4 d4d7";
            break;
        case iTermBoxDrawingCodeDownLightAndLeftHeavy:  // ┑
            components = @"a3d3 d3d7 a5d5";
            break;
        case iTermBoxDrawingCodeDownHeavyAndLeftLight:  // ┒
            components = @"a4e4 e4e7 c4c7";
            break;
        case iTermBoxDrawingCodeHeavyDownAndLeft:  // ┓
            components = @"a3e3 e3e7 a5c5 c5c7";
            break;
        case iTermBoxDrawingCodeLightUpAndRight:  // └
            components = @"d1d4 d4g4";
            break;
        case iTermBoxDrawingCodeUpLightAndRightHeavy:  // ┕
            components = @"d1d5 d5g5 d3g3";
            break;
        case iTermBoxDrawingCodeUpHeavyAndRightLight:  // ┖
            components = @"c1c4 c4g4 e1e4";
            break;
        case iTermBoxDrawingCodeHeavyUpAndRight:  // ┗
            components = @"c1c5 c5g5 e1e3 e3g3";
            break;
        case iTermBoxDrawingCodeLightUpAndLeft:  // ┘
            components = @"a4d4 d4d1";
            break;
        case iTermBoxDrawingCodeUpLightAndLeftHeavy:  // ┙
            components = @"a5d5 d5d1 a3d3";
            break;
        case iTermBoxDrawingCodeUpHeavyAndLeftLight:  // ┚
            components = @"a4e4 e4e1 c4c1";
            break;
        case iTermBoxDrawingCodeHeavyUpAndLeft:  // ┛
            components = @"a5e5 e5e1 a3c3 c3c1";
            break;
        case iTermBoxDrawingCodeLightVerticalAndRight:  // ├
            components = @"d1d7 d4g4";
            break;
        case iTermBoxDrawingCodeVerticalLightAndRightHeavy:  // ┝
            components = @"d1d7 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeUpHeavyAndRightDownLight:  // ┞
            components = @"c1c4 e1e4 e4g4 d4d7";
            break;
        case iTermBoxDrawingCodeDownHeavyAndRightUpLight:  // ┟
            components = @"d1d4 d4g4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndRightLight:  // ┠
            components = @"c1c7 e1e7 e4g4";
            break;
        case iTermBoxDrawingCodeDownLightAndRightUpHeavy:  // ┡
            components = @"c1c4 c4g4 e1e3 e3g3 d4d7";
            break;
        case iTermBoxDrawingCodeUpLightAndRightDownHeavy:  // ┢
            components = @"d1d4 c7c3 c3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndRight:  // ┣
            components = @"c1c7 e1e3 e3g3 g5e5 e5e7";
            break;
        case iTermBoxDrawingCodeLightVerticalAndLeft:  // ┤
            components = @"d1d7 a4d4";
            break;
        case iTermBoxDrawingCodeVerticalLightAndLeftHeavy:  // ┥
            components = @"d1d7 a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeUpHeavyAndLeftDownLight:  // ┦
            components = @"c1c4 e1e4 a4d4 d4d7";
            break;
        case iTermBoxDrawingCodeDownHeavyAndLeftUpLight:  // ┧
            components = @"d1d4 d4a4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndLeftLight:  // ┨
            components = @"a4c4 c1c7 e1e7";
            break;
        case iTermBoxDrawingCodeDownLightAndLeftUpHeavy:  // ┩
            components = @"c1c3 c3a3 e1e5 e5a5 d4d7";
            break;
        case iTermBoxDrawingCodeUpLightAndLeftDownHeavy:  // ┪
            components = @"a3d3 d3d7 a5c5 c5c7 d1d4";
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndLeft:  // ┫
            components = @"a3c3 c3c1 a5c5 c5c7 e1e7";
            break;
        case iTermBoxDrawingCodeLightDownAndHorizontal:  // ┬
            components = @"a4g4 d4d7";
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightDownLight:  // ┭
            components = @"a3d3 a5d5 d7d4 d4g4";
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftDownLight:  // ┮
            components = @"a4d4 d4d7 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeDownLightAndHorizontalHeavy:  // ┯
            components = @"a3g3 a5g5 d5d7";
            break;
        case iTermBoxDrawingCodeDownHeavyAndHorizontalLight:  // ┰
            components = @"a4g4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeRightLightAndLeftDownHeavy:  // ┱
            components = @"a3e3 e3e7 a5c5 c5c7 d4g4";
            break;
        case iTermBoxDrawingCodeLeftLightAndRightDownHeavy:  // ┲
            components = @"a4d4 c7c3 c3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeHeavyDownAndHorizontal:  // ┳
            components = @"a3g3 a5c5 c5c7 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeLightUpAndHorizontal:  // ┴
            components = @"a4g4 d1d4";
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightUpLight:  // ┵
            components = @"d1d4 d4g4 a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftUpLight:  // ┶
            components = @"a4d4 d4d1 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeUpLightAndHorizontalHeavy:  // ┷
            components = @"a3g3 a5g5 d1d4";
            break;
        case iTermBoxDrawingCodeUpHeavyAndHorizontalLight:  // ┸
            components = @"a4g4 c1c4 e1e4";
            break;
        case iTermBoxDrawingCodeRightLightAndLeftUpHeavy:  // ┹
            components = @"a3c3 c3c1 a5e5 e5e1 d4g4";
            break;
        case iTermBoxDrawingCodeLeftLightAndRightUpHeavy:  // ┺
            components = @"a4d4 c1c5 c5g5 d1d3 d3g3";
            break;
        case iTermBoxDrawingCodeHeavyUpAndHorizontal:  // ┻
            components = @"a5g5 a3c3 c3c1 e1e3 e3g3";
            break;
        case iTermBoxDrawingCodeLightVerticalAndHorizontal:  // ┼
            components = @"a4g4 d1d7";
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightVerticalLight:  // ┽
            components = @"d1d7 d4g4 a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftVerticalLight:  // ┾
            components = @"d1d7 a4d4 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeVerticalLightAndHorizontalHeavy:  // ┿
            components = @"d1d7 a3g3 a5g5";
            break;
        case iTermBoxDrawingCodeUpHeavyAndDownHorizontalLight:  // ╀
            components = @"a4g4 d4d7 c1c4 e1e4";
            break;
        case iTermBoxDrawingCodeDownHeavyAndUpHorizontalLight:  // ╁
            components = @"a4g4 d1d4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndHorizontalLight:  // ╂
            components = @"a4g4 c1c7 e1e7";
            break;
        case iTermBoxDrawingCodeLeftUpHeavyAndRightDownLight:  // ╃
            components = @"a3c3 c3c1 a5e5 e5e1 d7d4 d4g4";
            break;
        case iTermBoxDrawingCodeRightUpHeavyAndLeftDownLight:  // ╄
            components = @"a4d4 d4d7 c1c5 c5g5 e1e3 e3g3";
            break;
        case iTermBoxDrawingCodeLeftDownHeavyAndRightUpLight:  // ╅
            components = @"d1d4 d4g4 a3e3 e3e7 a5c5 c5c7";
            break;
        case iTermBoxDrawingCodeRightDownHeavyAndLeftUpLight:  // ╆
            components = @"a4d4 d4d1 c7c3 c3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeDownLightAndUpHorizontalHeavy:  // ╇
            components = @"a5g5 a3c3 c3c1 e1e3 e3g3 d4d7";
            break;
        case iTermBoxDrawingCodeUpLightAndDownHorizontalHeavy:  // ╈
            components = @"d1d4 a3g3 a5c5 c5c7 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeRightLightAndLeftVerticalHeavy:  // ╉
            components = @"a3c3 c3c1 a5c5 c5c7 e1e7 d4g4";
            break;
        case iTermBoxDrawingCodeLeftLightAndRightVerticalHeavy:  // ╊
            components = @"a4c4 c1c7 e1e3 e3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndHorizontal:  // ╋
            components = @"a3g3 a5g5 c1c7 e1e7";
            break;

        case iTermBoxDrawingCodeLightDoubleDashHorizontal:  // ╌
        case iTermBoxDrawingCodeHeavyDoubleDashHorizontal:  // ╍
        case iTermBoxDrawingCodeLightDoubleDashVertical:  // ╎
        case iTermBoxDrawingCodeHeavyDoubleDashVertical:  // ╏
            return nil;
            
        case iTermBoxDrawingCodeDoubleHorizontal:  // ═
            components = @"a2g2 a6g6";
            break;
        case iTermBoxDrawingCodeDoubleVertical:  // ║
            components = @"b1b7 f1f7";
            break;
        case iTermBoxDrawingCodeDownSingleAndRightDouble:  // ╒
            components = @"g2d2 d2d7 g6d6";
            break;
        case iTermBoxDrawingCodeDownDoubleAndRightSingle:  // ╓
            components = @"g4b4 b4b7 f4f7";
            break;
        case iTermBoxDrawingCodeDoubleDownAndRight:  // ╔
            components = @"g2b2 b2b7 g6f6 f6f7";
            break;
        case iTermBoxDrawingCodeDownSingleAndLeftDouble:  // ╕
            components = @"a2d2 d2d7 a6d6";
            break;
        case iTermBoxDrawingCodeDownDoubleAndLeftSingle:  // ╖
            components = @"a4f4 f4f7 b4b7";
            break;
        case iTermBoxDrawingCodeDoubleDownAndLeft:  // ╗
            components = @"a2f2 f2f7 a6b6 b6b7";
            break;
        case iTermBoxDrawingCodeUpSingleAndRightDouble:  // ╘
            components = @"d1d6 d6g6 d2g2";
            break;
        case iTermBoxDrawingCodeUpDoubleAndRightSingle:  // ╙
            components = @"b1b4 b4g4 f1f4";
            break;
        case iTermBoxDrawingCodeDoubleUpAndRight:  // ╚
            components = @"b1b6 b6g6 f1f2 f2g2";
            break;
        case iTermBoxDrawingCodeUpSingleAndLeftDouble:  // ╛
            components = @"a2d2 a6d6 d6d1";
            break;
        case iTermBoxDrawingCodeUpDoubleAndLeftSingle:  // ╜
            components = @"a4f4 f4f1 b4b1";
            break;
        case iTermBoxDrawingCodeDoubleUpAndLeft:  // ╝
            components = @"a2b2 b2b1 a6f6 f6f1";
            break;
        case iTermBoxDrawingCodeVerticalSingleAndRightDouble:  // ╞
            components = @"d1d7 d2g2 d6g6";
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndRightSingle:  // ╟
            components = @"b1b7 f1f7 f4g4";
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndRight:  // ╠
            components = @"b1b7 f1f2 f2g2 f7f6 f6g6";
            break;
        case iTermBoxDrawingCodeVerticalSingleAndLeftDouble:  // ╡
            components = @"d1d7 a2d2 a6d6";
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndLeftSingle:  // ╢
            components = @"a4b4 b1b7 f1f7";
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndLeft:  // ╣
            components = @"a2b2 b2b1 a6b6 b6b7 f1f7";
            break;
        case iTermBoxDrawingCodeDownSingleAndHorizontalDouble:  // ╤
            components = @"a2g2 a6g6 d6d7";
            break;
        case iTermBoxDrawingCodeDownDoubleAndHorizontalSingle:  // ╥
            components = @"a4g4 b4b7 f4f7";
            break;
        case iTermBoxDrawingCodeDoubleDownAndHorizontal:  // ╦
            components = @"a2g2 a6b6 b6b7 f7f6 f6g6";
            break;
        case iTermBoxDrawingCodeUpSingleAndHorizontalDouble:  // ╧
            components = @"a6g6 a2g2 d1d2";
            break;
        case iTermBoxDrawingCodeUpDoubleAndHorizontalSingle:  // ╨
            components = @"a4g4 b1b4 f1f4";
            break;
        case iTermBoxDrawingCodeDoubleUpAndHorizontal:  // ╩
            components = @"a2b2 b2b1 f1f2 f2g2 a6g6";
            break;
        case iTermBoxDrawingCodeVerticalSingleAndHorizontalDouble:  // ╪
            components = @"a2g2 a6g6 d1d7";
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndHorizontalSingle:  // ╫
            components = @"b1b7 f1f7 a4g4";
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndHorizontal:  // ╬
            components = @"a2b2 b2b1 f1f2 f2g2 g6f6 f6f7 b7b6 b6a6";
            break;
        case iTermBoxDrawingCodeLightArcDownAndRight:  // ╭
        case iTermBoxDrawingCodeLightArcDownAndLeft:  // ╮
        case iTermBoxDrawingCodeLightArcUpAndLeft:  // ╯
        case iTermBoxDrawingCodeLightArcUpAndRight:  // ╰
        case iTermBoxDrawingCodeLightDiagonalUpperRightToLowerLeft:  // ╱
        case iTermBoxDrawingCodeLightDiagonalUpperLeftToLowerRight:  // ╲
        case iTermBoxDrawingCodeLightDiagonalCross:  // ╳
            return nil;
            
        case iTermBoxDrawingCodeLightLeft:  // ╴
            components = @"a4d4";
            break;
        case iTermBoxDrawingCodeLightUp:  // ╵
            components = @"d1d4";
            break;
        case iTermBoxDrawingCodeLightRight:  // ╶
            components = @"d4g4";
            break;
        case iTermBoxDrawingCodeLightDown:  // ╷
            components = @"d4d7";
            break;
        case iTermBoxDrawingCodeHeavyLeft:  // ╸
            components = @"a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeHeavyUp:  // ╹
            components = @"c1c4 e1e4";
            break;
        case iTermBoxDrawingCodeHeavyRight:  // ╺
            components = @"d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeHeavyDown:  // ╻
            components = @"c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeLightLeftAndHeavyRight:  // ╼
            components = @"a4d4 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeLightUpAndHeavyDown:  // ╽
            components = @"d1d4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeHeavyLeftAndLightRight:  // ╾
            components = @"a3d3 a5d5 d4g4";
            break;
        case iTermBoxDrawingCodeHeavyUpAndLightDown:  // ╿
            components = @"c1c4 e1e4 d4d7";
            break;
    }
    
    if (!components) {
        return nil;
    }
    
    CGFloat horizontalCenter = cellSize.width / 2.0;
    CGFloat verticalCenter = cellSize.height / 2.0;
    
    const char *bytes = [components UTF8String];
    NSBezierPath *path = [NSBezierPath bezierPath];
    int lastX = -1;
    int lastY = -1;
    int i = 0;
    int length = components.length;
    CGFloat xs[] = { 0, horizontalCenter - 1, horizontalCenter - 0.5, horizontalCenter, horizontalCenter + 0.5, horizontalCenter + 1, cellSize.width };
    CGFloat ys[] = { 0, verticalCenter - 1, verticalCenter - 0.5, verticalCenter, verticalCenter + 0.5, verticalCenter + 1, cellSize.height };
    while (i + 4 <= length) {
        int x1 = bytes[i++] - 'a';
        int y1 = bytes[i++] - '1';
        int x2 = bytes[i++] - 'a';
        int y2 = bytes[i++] - '1';
        
        assert(x1 == x2 || y1 == y2);
        if (x1 != lastX || y1 != lastY) {
            [path moveToPoint:NSMakePoint(xs[x1], ys[y1])];
        }
        [path lineToPoint:NSMakePoint(xs[x2], ys[y2])];
        
        i++;
        
        lastX = x2;
        lastY = y2;
    }
    
    return @[ path ];
}

+ (NSBezierPath *)bezierPathForPoints:(NSArray *)points
                   extendPastCenterBy:(NSPoint)extension
                             cellSize:(NSSize)cellSize {
    CGFloat cx = cellSize.width / 2.0;
    CGFloat cy = cellSize.height / 2.0;
    CGFloat xs[] = { 0, cx - 1, cx, cx + 1, cellSize.width };
    CGFloat ys[] = { 0, cy - 1, cy, cy + 1, cellSize.height };
    NSBezierPath *path = [NSBezierPath bezierPath];
    BOOL first = YES;
    for (NSNumber *n in points) {
        CGFloat x = xs[n.intValue % 5];
        CGFloat y = ys[n.intValue / 5];
        if ((n.intValue % 5 == 2) && (n.intValue / 5 == 2)) {
            x += extension.x;
            y += extension.y;
        }
        NSPoint p = NSMakePoint(x, y);
        if (first) {
            [path moveToPoint:p];
            first = NO;
        } else {
            [path lineToPoint:p];
        }
    }
    return path;
}

@end
