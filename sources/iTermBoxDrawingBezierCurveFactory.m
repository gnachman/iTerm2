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
    NSString *const iTermBoxDrawingComponentLightUp = @"iTermBoxDrawingComponentLightUp";
    NSString *const iTermBoxDrawingComponentLightRight = @"iTermBoxDrawingComponentLightRight";
    NSString *const iTermBoxDrawingComponentLightDown = @"iTermBoxDrawingComponentLightDown";
    NSString *const iTermBoxDrawingComponentLightLeft = @"iTermBoxDrawingComponentLightLeft";
    NSString *const iTermBoxDrawingComponentLightHorizontal = @"iTermBoxDrawingComponentLightHorizontal";
    NSString *const iTermBoxDrawingComponentLightVertical = @"iTermBoxDrawingComponentLightVertical";
    
    NSString *const iTermBoxDrawingComponentHeavyUp = @"iTermBoxDrawingComponentHeavyUp";
    NSString *const iTermBoxDrawingComponentHeavyRight = @"iTermBoxDrawingComponentHeavyRight";
    NSString *const iTermBoxDrawingComponentHeavyDown = @"iTermBoxDrawingComponentHeavyDown";
    NSString *const iTermBoxDrawingComponentHeavyLeft = @"iTermBoxDrawingComponentHeavyLeft";
    NSString *const iTermBoxDrawingComponentHeavyHorizontal = @"iTermBoxDrawingComponentHeavyHorizontal";
    NSString *const iTermBoxDrawingComponentHeavyVertical = @"iTermBoxDrawingComponentHeavyVertical";
    
    NSString *const iTermBoxDrawingComponentDoubleUp = @"iTermBoxDrawingComponentDoubleUp";
    NSString *const iTermBoxDrawingComponentDoubleRight = @"iTermBoxDrawingComponentDoubleRight";
    NSString *const iTermBoxDrawingComponentDoubleDown = @"iTermBoxDrawingComponentDoubleDown";
    NSString *const iTermBoxDrawingComponentDoubleLeft = @"iTermBoxDrawingComponentDoubleLeft";
    NSString *const iTermBoxDrawingComponentDoubleHorizontal = @"iTermBoxDrawingComponentDoubleHorizontal";
    NSString *const iTermBoxDrawingComponentDoubleVertical = @"iTermBoxDrawingComponentDoubleVertical";

    static NSString *const iTermBoxDrawingComponentInnerDownRight = @"iTermBoxDrawingComponentInnerDownRight";
    static NSString *const iTermBoxDrawingComponentOuterDownRight = @"iTermBoxDrawingComponentOuterDownRight";
    static NSString *const iTermBoxDrawingComponentInnerDownLeft = @"iTermBoxDrawingComponentInnerDownLeft";
    static NSString *const iTermBoxDrawingComponentOuterDownLeft = @"iTermBoxDrawingComponentOuterDownLeft";
    static NSString *const iTermBoxDrawingComponentInnerTopRight = @"iTermBoxDrawingComponentInnerTopRight";
    static NSString *const iTermBoxDrawingComponentOuterTopRight = @"iTermBoxDrawingComponentOuterTopRight";
    static NSString *const iTermBoxDrawingComponentInnerTopLeft = @"iTermBoxDrawingComponentInnerTopLeft";
    static NSString *const iTermBoxDrawingComponentOuterTopLeft = @"iTermBoxDrawingComponentOuterTopLeft";
    static NSString *const iTermBoxDrawingComponentVerticalShiftedLeft = @"iTermBoxDrawingComponentVerticalShiftedLeft";
    static NSString *const iTermBoxDrawingComponentVerticalShiftedRight = @"iTermBoxDrawingComponentVerticalShiftedRight";
    static NSString *const iTermBoxDrawingComponentHorizontalShiftedUp = @"iTermBoxDrawingComponentHorizontalShiftedUp";
    static NSString *const iTermBoxDrawingComponentHorizontalShiftedDown = @"iTermBoxDrawingComponentHorizontalShiftedDown";

    NSArray<NSString *> *all = @[ iTermBoxDrawingComponentLightUp,
                                  iTermBoxDrawingComponentLightRight,
                                  iTermBoxDrawingComponentLightDown,
                                  iTermBoxDrawingComponentLightLeft,
                                  iTermBoxDrawingComponentLightHorizontal,
                                  iTermBoxDrawingComponentLightVertical,
                                  iTermBoxDrawingComponentHeavyUp,
                                  iTermBoxDrawingComponentHeavyRight,
                                  iTermBoxDrawingComponentHeavyDown,
                                  iTermBoxDrawingComponentHeavyLeft,
                                  iTermBoxDrawingComponentHeavyHorizontal,
                                  iTermBoxDrawingComponentHeavyVertical,
                                  iTermBoxDrawingComponentDoubleUp,
                                  iTermBoxDrawingComponentDoubleRight,
                                  iTermBoxDrawingComponentDoubleDown,
                                  iTermBoxDrawingComponentDoubleLeft,
                                  iTermBoxDrawingComponentDoubleHorizontal,
                                  iTermBoxDrawingComponentDoubleVertical,
                                  iTermBoxDrawingComponentInnerDownRight,
                                  iTermBoxDrawingComponentOuterDownRight,
                                  iTermBoxDrawingComponentInnerDownLeft,
                                  iTermBoxDrawingComponentOuterDownLeft,
                                  iTermBoxDrawingComponentInnerTopRight,
                                  iTermBoxDrawingComponentOuterTopRight,
                                  iTermBoxDrawingComponentInnerTopLeft,
                                  iTermBoxDrawingComponentOuterTopLeft,
                                  iTermBoxDrawingComponentVerticalShiftedLeft,
                                  iTermBoxDrawingComponentVerticalShiftedRight,
                                  iTermBoxDrawingComponentHorizontalShiftedUp,
                                  iTermBoxDrawingComponentHorizontalShiftedDown, ];

    //  0    1  2  3    4
    //
    //  5    6  7  8    9
    // 10   11 12 13   14
    // 15   16 17 18   19
    //
    // 20   21 22 23   24

    NSDictionary *componentPoints =
        @{ iTermBoxDrawingComponentLightUp:          @[ @[ @12, @2  ] ],
           iTermBoxDrawingComponentLightRight:       @[ @[ @12, @14 ] ],
           iTermBoxDrawingComponentLightDown:        @[ @[ @12, @22 ] ],
           iTermBoxDrawingComponentLightLeft:        @[ @[ @12, @10 ] ],
           iTermBoxDrawingComponentLightHorizontal:  @[ @[ @10, @14 ] ],
           iTermBoxDrawingComponentLightVertical:    @[ @[ @2,  @22 ] ],

           iTermBoxDrawingComponentHeavyUp:          @[ @[ @12, @2  ] ],
           iTermBoxDrawingComponentHeavyRight:       @[ @[ @12, @14 ] ],
           iTermBoxDrawingComponentHeavyDown:        @[ @[ @12, @22 ] ],
           iTermBoxDrawingComponentHeavyLeft:        @[ @[ @12, @10 ] ],
           iTermBoxDrawingComponentHeavyHorizontal:  @[ @[ @10, @14 ] ],
           iTermBoxDrawingComponentHeavyVertical:    @[ @[ @2,  @22 ] ],

           iTermBoxDrawingComponentDoubleUp:         @[ @[ @11, @1 ], @[ @13, @3 ] ],
           iTermBoxDrawingComponentDoubleRight:      @[ @[ @7,  @9 ], @[ @17, @19 ] ],
           iTermBoxDrawingComponentDoubleDown:       @[ @[ @11, @21], @[ @13, @23 ] ],
           iTermBoxDrawingComponentDoubleLeft:       @[ @[ @7,  @5 ], @[ @17, @15 ] ],
           iTermBoxDrawingComponentDoubleHorizontal: @[ @[ @5,  @9 ], @[ @15, @19 ] ],
           iTermBoxDrawingComponentDoubleVertical:   @[ @[ @1,  @21], @[ @3,  @23 ] ],
           
           iTermBoxDrawingComponentInnerDownRight:        @[ @[ @23, @18, @19 ] ],
           iTermBoxDrawingComponentOuterDownRight:        @[ @[ @21, @6, @9 ] ],
           iTermBoxDrawingComponentInnerDownLeft:         @[ @[ @21, @16, @15 ] ],
           iTermBoxDrawingComponentOuterDownLeft:         @[ @[ @23, @8, @5 ] ],
           iTermBoxDrawingComponentInnerTopRight:         @[ @[ @3, @8, @9 ] ],
           iTermBoxDrawingComponentOuterTopRight:         @[ @[ @1, @16, @19 ] ],
           iTermBoxDrawingComponentInnerTopLeft:          @[ @[ @1, @6, @5 ] ],
           iTermBoxDrawingComponentOuterTopLeft:          @[ @[ @3, @18, @15 ] ],
           iTermBoxDrawingComponentVerticalShiftedLeft:   @[ @[ @1, @21 ] ],
           iTermBoxDrawingComponentVerticalShiftedRight:  @[ @[ @3, @23 ] ],
           iTermBoxDrawingComponentHorizontalShiftedUp:   @[ @[ @5, @9 ] ],
           iTermBoxDrawingComponentHorizontalShiftedDown: @[ @[ @15, @19 ] ]
        };
    NSArray *components = nil;
    
    switch (code) {
        case iTermBoxDrawingCodeLightHorizontal:  // ─
            components = @[ iTermBoxDrawingComponentLightHorizontal ];
            break;
        case iTermBoxDrawingCodeHeavyHorizontal:  // ━
            components = @[ iTermBoxDrawingComponentHeavyHorizontal ];
            break;
        case iTermBoxDrawingCodeLightVertical:  // │
            components = @[ iTermBoxDrawingComponentLightVertical];
            break;
        case iTermBoxDrawingCodeHeavyVertical:  // ┃
            components = @[ iTermBoxDrawingComponentHeavyVertical];
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
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeDownLightAndRightHeavy:  // ┍
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeDownHeavyAndRightLight:  // ┎
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeHeavyDownAndRight:  // ┏
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeLightDownAndLeft:  // ┐
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeDownLightAndLeftHeavy:  // ┑
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyLeft ];
            break;
        case iTermBoxDrawingCodeDownHeavyAndLeftLight:  // ┒
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeHeavyDownAndLeft:  // ┓
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyLeft ];
            break;
        case iTermBoxDrawingCodeLightUpAndRight:  // └
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeUpLightAndRightHeavy:  // ┕
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeUpHeavyAndRightLight:  // ┖
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeHeavyUpAndRight:  // ┗
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeLightUpAndLeft:  // ┘
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeUpLightAndLeftHeavy:  // ┙
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentHeavyLeft ];
            break;
        case iTermBoxDrawingCodeUpHeavyAndLeftLight:  // ┚
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeHeavyUpAndLeft:  // ┛
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentHeavyLeft ];
            break;
        case iTermBoxDrawingCodeLightVerticalAndRight:  // ├
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeVerticalLightAndRightHeavy:  // ┝
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeUpHeavyAndRightDownLight:  // ┞
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeDownHeavyAndRightUpLight:  // ┟
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndRightLight:  // ┠
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeDownLightAndRightUpHeavy:  // ┡
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeUpLightAndRightDownHeavy:  // ┢
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndRight:  // ┣
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeLightVerticalAndLeft:  // ┤
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeVerticalLightAndLeftHeavy:  // ┥
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentHeavyLeft ];
            break;
        case iTermBoxDrawingCodeUpHeavyAndLeftDownLight:  // ┦
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeDownHeavyAndLeftUpLight:  // ┧
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndLeftLight:  // ┨
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeDownLightAndLeftUpHeavy:  // ┩
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeUpLightAndLeftDownHeavy:  // ┪
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndLeft:  // ┫
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeLightDownAndHorizontal:  // ┬
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightDownLight:  // ┭
            components = @[ iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftDownLight:  // ┮
            components = @[ iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeDownLightAndHorizontalHeavy:  // ┯
            components = @[ iTermBoxDrawingComponentHeavyHorizontal,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeDownHeavyAndHorizontalLight:  // ┰
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentHeavyDown ];
            break;
        case iTermBoxDrawingCodeRightLightAndLeftDownHeavy:  // ┱
            components = @[ iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentHeavyDown ];
            break;
        case iTermBoxDrawingCodeLeftLightAndRightDownHeavy:  // ┲
            components = @[ iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentHeavyDown ];
            break;
        case iTermBoxDrawingCodeHeavyDownAndHorizontal:  // ┳
            components = @[ iTermBoxDrawingComponentHeavyHorizontal,
                            iTermBoxDrawingComponentHeavyDown ];
            break;
        case iTermBoxDrawingCodeLightUpAndHorizontal:  // ┴
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightUpLight:  // ┵
            components = @[ iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftUpLight:  // ┶
            components = @[ iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeUpLightAndHorizontalHeavy:  // ┷
            components = @[ iTermBoxDrawingComponentHeavyHorizontal,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeUpHeavyAndHorizontalLight:  // ┸
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeRightLightAndLeftUpHeavy:  // ┹
            components = @[ iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeLeftLightAndRightUpHeavy:  // ┺
            components = @[ iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeHeavyUpAndHorizontal:  // ┻
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeLightVerticalAndHorizontal:  // ┼
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentLightVertical ];
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightVerticalLight:  // ┽
            components = @[ iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightVertical ];
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftVerticalLight:  // ┾
            components = @[ iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentLightVertical ];
            break;
        case iTermBoxDrawingCodeVerticalLightAndHorizontalHeavy:  // ┿
            components = @[ iTermBoxDrawingComponentHeavyHorizontal,
                            iTermBoxDrawingComponentLightVertical ];
            break;
        case iTermBoxDrawingCodeUpHeavyAndDownHorizontalLight:  // ╀
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentLightVertical ];
            break;
        case iTermBoxDrawingCodeDownHeavyAndUpHorizontalLight:  // ╁
            components = @[ iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndHorizontalLight:  // ╂
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentHeavyVertical ];
            break;
        case iTermBoxDrawingCodeLeftUpHeavyAndRightDownLight:  // ╃
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeRightUpHeavyAndLeftDownLight:  // ╄
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeLeftDownHeavyAndRightUpLight:  // ╅
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeRightDownHeavyAndLeftUpLight:  // ╆
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeDownLightAndUpHorizontalHeavy:  // ╇
            components = @[ iTermBoxDrawingComponentHeavyUp,
                            iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyHorizontal ];
            break;
        case iTermBoxDrawingCodeUpLightAndDownHorizontalHeavy:  // ╈
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentHeavyDown,
                            iTermBoxDrawingComponentHeavyHorizontal ];
            break;
        case iTermBoxDrawingCodeRightLightAndLeftVerticalHeavy:  // ╉
            components = @[ iTermBoxDrawingComponentLightRight,
                            iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentHeavyVertical ];
            break;
        case iTermBoxDrawingCodeLeftLightAndRightVerticalHeavy:  // ╊
            components = @[ iTermBoxDrawingComponentHeavyRight,
                            iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyVertical ];
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndHorizontal:  // ╋
            components = @[ iTermBoxDrawingComponentHeavyHorizontal,
                            iTermBoxDrawingComponentHeavyVertical ];
            break;

        case iTermBoxDrawingCodeLightDoubleDashHorizontal:  // ╌
        case iTermBoxDrawingCodeHeavyDoubleDashHorizontal:  // ╍
        case iTermBoxDrawingCodeLightDoubleDashVertical:  // ╎
        case iTermBoxDrawingCodeHeavyDoubleDashVertical:  // ╏
            return nil;
            
        case iTermBoxDrawingCodeDoubleHorizontal:  // ═
            components = @[ iTermBoxDrawingComponentHorizontalShiftedDown, iTermBoxDrawingComponentHorizontalShiftedUp ];
            break;
        case iTermBoxDrawingCodeDoubleVertical:  // ║
            components = @[ iTermBoxDrawingComponentVerticalShiftedLeft, iTermBoxDrawingComponentVerticalShiftedRight ];
            break;
        case iTermBoxDrawingCodeDownSingleAndRightDouble:  // ╒
            components = @[ iTermBoxDrawingComponentDoubleRight,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeDownDoubleAndRightSingle:  // ╓
            components = @[ iTermBoxDrawingComponentDoubleUp,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeDoubleDownAndRight:  // ╔
            components = @[ iTermBoxDrawingComponentInnerDownRight,
                            iTermBoxDrawingComponentOuterDownRight ];
            break;
        case iTermBoxDrawingCodeDownSingleAndLeftDouble:  // ╕
            components = @[ iTermBoxDrawingComponentDoubleLeft,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeDownDoubleAndLeftSingle:  // ╖
            components = @[ iTermBoxDrawingComponentDoubleUp,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeDoubleDownAndLeft:  // ╗
            components = @[ iTermBoxDrawingComponentInnerDownLeft,
                            iTermBoxDrawingComponentOuterDownLeft ];
            break;
        case iTermBoxDrawingCodeUpSingleAndRightDouble:  // ╘
            components = @[ iTermBoxDrawingComponentDoubleRight,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeUpDoubleAndRightSingle:  // ╙
            components = @[ iTermBoxDrawingComponentDoubleDown,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeDoubleUpAndRight:  // ╚
            components = @[ iTermBoxDrawingComponentInnerTopRight,
                            iTermBoxDrawingComponentOuterTopRight ];
            break;
        case iTermBoxDrawingCodeUpSingleAndLeftDouble:  // ╛
            components = @[ iTermBoxDrawingComponentDoubleLeft,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeUpDoubleAndLeftSingle:  // ╜
            components = @[ iTermBoxDrawingComponentDoubleDown,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeDoubleUpAndLeft:  // ╝
            components = @[ iTermBoxDrawingComponentInnerTopLeft,
                            iTermBoxDrawingComponentOuterTopLeft ];
            break;
        case iTermBoxDrawingCodeVerticalSingleAndRightDouble:  // ╞
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentDoubleRight ];
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndRightSingle:  // ╟
            components = @[ iTermBoxDrawingComponentDoubleVertical,
                            iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndRight:  // ╠
            components = @[ iTermBoxDrawingComponentVerticalShiftedLeft,
                            iTermBoxDrawingComponentInnerTopRight,
                            iTermBoxDrawingComponentInnerDownRight ];
            break;
        case iTermBoxDrawingCodeVerticalSingleAndLeftDouble:  // ╡
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentDoubleLeft ];
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndLeftSingle:  // ╢
            components = @[ iTermBoxDrawingComponentDoubleVertical,
                            iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndLeft:  // ╣
            components = @[ iTermBoxDrawingComponentVerticalShiftedRight,
                            iTermBoxDrawingComponentInnerTopLeft,
                            iTermBoxDrawingComponentInnerDownLeft ];
            break;
        case iTermBoxDrawingCodeDownSingleAndHorizontalDouble:  // ╤
            components = @[ iTermBoxDrawingComponentDoubleHorizontal,
                            iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeDownDoubleAndHorizontalSingle:  // ╥
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentDoubleDown ];
            break;
        case iTermBoxDrawingCodeDoubleDownAndHorizontal:  // ╦
            components = @[ iTermBoxDrawingComponentHorizontalShiftedUp,
                            iTermBoxDrawingComponentInnerDownRight,
                            iTermBoxDrawingComponentInnerDownLeft ];
            break;
        case iTermBoxDrawingCodeUpSingleAndHorizontalDouble:  // ╧
            components = @[ iTermBoxDrawingComponentDoubleHorizontal,
                            iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeUpDoubleAndHorizontalSingle:  // ╨
            components = @[ iTermBoxDrawingComponentLightHorizontal,
                            iTermBoxDrawingComponentDoubleUp ];
            break;
        case iTermBoxDrawingCodeDoubleUpAndHorizontal:  // ╩
            components = @[ iTermBoxDrawingComponentHorizontalShiftedDown,
                            iTermBoxDrawingComponentInnerTopRight,
                            iTermBoxDrawingComponentInnerTopLeft ];
            break;
        case iTermBoxDrawingCodeVerticalSingleAndHorizontalDouble:  // ╪
            components = @[ iTermBoxDrawingComponentLightVertical,
                            iTermBoxDrawingComponentDoubleHorizontal ];
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndHorizontalSingle:  // ╫
            components = @[ iTermBoxDrawingComponentDoubleVertical,
                            iTermBoxDrawingComponentLightHorizontal ];
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndHorizontal:  // ╬
            components = @[ iTermBoxDrawingComponentInnerDownRight,
                            iTermBoxDrawingComponentInnerDownLeft,
                            iTermBoxDrawingComponentInnerTopRight,
                            iTermBoxDrawingComponentInnerTopLeft ];
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
            components = @[ iTermBoxDrawingComponentLightLeft ];
            break;
        case iTermBoxDrawingCodeLightUp:  // ╵
            components = @[ iTermBoxDrawingComponentLightUp ];
            break;
        case iTermBoxDrawingCodeLightRight:  // ╶
            components = @[ iTermBoxDrawingComponentLightRight ];
            break;
        case iTermBoxDrawingCodeLightDown:  // ╷
            components = @[ iTermBoxDrawingComponentLightDown ];
            break;
        case iTermBoxDrawingCodeHeavyLeft:  // ╸
            components = @[ iTermBoxDrawingComponentHeavyLeft ];
            break;
        case iTermBoxDrawingCodeHeavyUp:  // ╹
            components = @[ iTermBoxDrawingComponentHeavyUp ];
            break;
        case iTermBoxDrawingCodeHeavyRight:  // ╺
            components = @[ iTermBoxDrawingComponentHeavyRight ];
            break;
        case iTermBoxDrawingCodeHeavyDown:  // ╻
            components = @[ iTermBoxDrawingComponentHeavyDown ];
            break;
        case iTermBoxDrawingCodeLightLeftAndHeavyRight:  // ╼
            components = @[ iTermBoxDrawingComponentLightLeft,
                            iTermBoxDrawingComponentHeavyRight];
            break;
        case iTermBoxDrawingCodeLightUpAndHeavyDown:  // ╽
            components = @[ iTermBoxDrawingComponentLightUp,
                            iTermBoxDrawingComponentHeavyDown];
            break;
        case iTermBoxDrawingCodeHeavyLeftAndLightRight:  // ╾
            components = @[ iTermBoxDrawingComponentHeavyLeft,
                            iTermBoxDrawingComponentLightRight];
            break;
        case iTermBoxDrawingCodeHeavyUpAndLightDown:  // ╿
            components = @[ iTermBoxDrawingComponentLightDown,
                            iTermBoxDrawingComponentHeavyUp];
            break;
    }

    NSArray *singles = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return ![string containsString:@"Double"];
    }];
    NSArray *doubles = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return [string containsString:@"Double"];
    }];
    NSArray *fulls = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return [string containsString:@"Vertical"] || [string containsString:@"Horizontal"];
    }];
    NSArray *halfs = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return !([string containsString:@"Vertical"] || [string containsString:@"Horizontal"]);
    }];
    NSArray *lights = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return [string containsString:@"Light"];
    }];
    NSArray *doubleInternals = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return ([string containsString:@"Shifted"] ||
                [string containsString:@"Inner"] ||
                [string containsString:@"Outer"]);
    }];
    NSArray *heavys = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return [string containsString:@"Heavy"];
    }];
    NSArray *rights = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return [string containsString:@"Right"];
    }];
    NSArray *horizontals = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return ([string containsString:@"Left"] ||
                [string containsString:@"Right"] ||
                [string containsString:@"Horizontal"]);
    }];
    NSArray *verticals = [all filteredArrayUsingBlock:^BOOL(NSString *string) {
        return ([string containsString:@"Up"] ||
                [string containsString:@"Down"] ||
                [string containsString:@"Vertical"]);
    }];

    // Need to handle intersection specially if double meets a perpindicualr.
    NSArray *doubleComponents = [components intersectArray:doubles];
    BOOL doubleIntersectsPerpindicular = NO;
    if (doubleComponents.count) {
        NSString *aDouble = doubleComponents.firstObject;
        BOOL doubleIsHorizontal = [horizontals containsObject:aDouble];
        BOOL hasPerp;
        if (doubleIsHorizontal) {
            hasPerp = [[components intersectArray:verticals] count] > 0;
        } else {
            hasPerp = [[components intersectArray:horizontals] count] > 0;
        }
        if (hasPerp) {
            doubleIntersectsPerpindicular = YES;
        }
    }
    
    BOOL twoHalves = (components.count == 2 && [[halfs intersectArray:components] count] == 2);
    BOOL twoPerpindicular = (components.count == 2 &&
                             [[horizontals intersectArray:components] count] == 1 &&
                             [[verticals intersectArray:components] count] == 1);
    BOOL twoPerpindicularHalves = (twoHalves && twoPerpindicular);
    BOOL anyDouble = doubleComponents.count > 0;
    
    NSBezierPath *heavy = [NSBezierPath bezierPath];
    [heavy setLineWidth:2];
    NSBezierPath *light = [NSBezierPath bezierPath];
    [light setLineWidth:1];

    NSPoint extensionForSingle = NSMakePoint(0, 0);
    if (doubleIntersectsPerpindicular) {
        NSString *doubleComponent = [[components intersectArray:doubles] firstObject];
        NSString *singleComponent = [[components intersectArray:singles] firstObject];
        if ([[components intersectArray:singles] count] == 1) {
            // Mix of single and double.
            if ([[components intersectArray:halfs] count] == 2) {
                // Both halfs. Make single longer.
                // ╒ ╓ ╕ ╘ ╙ ╖ ╛ ╜
                if (singleComponent == iTermBoxDrawingComponentLightDown) {
                    extensionForSingle.y = -1.5;
                } else if (singleComponent == iTermBoxDrawingComponentLightLeft) {
                    extensionForSingle.x = 1.5;
                } else if (singleComponent == iTermBoxDrawingComponentLightUp) {
                    extensionForSingle.y = 1.5;
                } else if (singleComponent == iTermBoxDrawingComponentLightRight) {
                    extensionForSingle.x = -1.5;
                }
            } else if ([fulls containsObject:doubleComponent] &&
                       [halfs containsObject:singleComponent]) {
                // One is full length. No fancy corner needed. Make single shorter.
                // ╟ ╢ ╤ ╧
                if (singleComponent == iTermBoxDrawingComponentLightDown) {
                    extensionForSingle.y = 1.5;
                } else if (singleComponent == iTermBoxDrawingComponentLightLeft) {
                    extensionForSingle.x = -1.5;
                } else if (singleComponent == iTermBoxDrawingComponentLightUp) {
                    extensionForSingle.y = -1.5;
                } else if (singleComponent == iTermBoxDrawingComponentLightRight) {
                    extensionForSingle.x = 1.5;
                }
            }
        }
    }
    if (components) {
        for (NSInteger i = 0; i < components.count; i++) {
            NSString *component = components[i];

            NSPoint extension = NSMakePoint(0, 0);
            if (twoPerpindicularHalves && !anyDouble && [horizontals containsObject:component]) {
                // Extend horizontal line where single half-lines meet.
                BOOL verticalIsHeavy = [heavys containsObject:components[1 - i]];
                if (verticalIsHeavy) {
                    extension.x = 1;
                } else {
                    extension.x = 0.5;
                }
                if ([rights containsObject:component]) {
                    extension.x *= -1;
                }
            } else if ([singles containsObject:component]) {
                // Tweak single line when single meets double.
                extension = extensionForSingle;
            }
            
            for (NSArray *points in componentPoints[component]) {
                NSBezierPath *subpath = [self bezierPathForPoints:points
                                               extendPastCenterBy:extension
                                                         cellSize:cellSize];
                
                if ([heavys containsObject:component]) {
                    [heavy appendBezierPath:subpath];
                } else {
                    [light appendBezierPath:subpath];
                }
            }
        }
    }

    return @[ heavy, light ];
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
