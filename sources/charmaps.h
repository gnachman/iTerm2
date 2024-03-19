/* Derived from linux/drivers/char/consolemap.c, GNU GPL:ed */
#import <Foundation/Foundation.h>

/*
 	    0	1	2	3	4	5	6	7	8	9	A	B	C	D	E	F
U+250x	─	━	│	┃	┄	┅	┆	┇	┈	┉	┊	┋	┌	┍	┎	┏
U+251x	┐	┑	┒	┓	└	┕	┖	┗	┘	┙	┚	┛	├	┝	┞	┟
U+252x	┠	┡	┢	┣	┤	┥	┦	┧	┨	┩	┪	┫	┬	┭	┮	┯
U+253x	┰	┱	┲	┳	┴	┵	┶	┷	┸	┹	┺	┻	┼	┽	┾	┿
U+254x	╀	╁	╂	╃	╄	╅	╆	╇	╈	╉	╊	╋	╌	╍	╎	╏
U+255x	═	║	╒	╓	╔	╕	╖	╗	╘	╙	╚	╛	╜	╝	╞	╟
U+256x	╠	╡	╢	╣	╤	╥	╦	╧	╨	╩	╪	╫	╬	╭	╮	╯
U+257x	╰	╱	╲	╳	╴	╵	╶	╷	╸	╹	╺	╻	╼	╽	╾	╿
U+258x  ▀   ▁   ▂   ▃   ▄   ▅   ▆   ▇   █   ▉   ▊   ▋   ▌   ▍   ▎   ▏
U+259x  ▐   ░   ▒   ▓   ▔   ▕   ▖   ▗   ▘   ▙   ▚   ▛   ▜   ▝   ▞   ▟
*/

#define iTermBoxDrawingCodeMin 0x2500
#define iTermBoxDrawingCodeMax 0x2580

typedef NS_ENUM(unichar, iTermBoxDrawingCode) {
    iTermBoxDrawingCodeLightHorizontal = 0x2500,  // ─
    iTermBoxDrawingCodeHeavyHorizontal = 0x2501,  // ━

    iTermBoxDrawingCodeLightVertical = 0x2502,  // │
    iTermBoxDrawingCodeHeavyVertical = 0x2503,  // ┃

    iTermBoxDrawingCodeLightTripleDashHorizontal = 0x2504,  // ┄
    iTermBoxDrawingCodeHeavyTripleDashHorizontal = 0x2505,  // ┅

    iTermBoxDrawingCodeLightTripleDashVertical = 0x2506,  // ┆
    iTermBoxDrawingCodeHeavyTripleDashVertical = 0x2507,  // ┇

    iTermBoxDrawingCodeLightQuadrupleDashHorizontal = 0x2508,  // ┈
    iTermBoxDrawingCodeHeavyQuadrupleDashHorizontal = 0x2509,  // ┉

    iTermBoxDrawingCodeLightQuadrupleDashVertical = 0x250A,  // ┊
    iTermBoxDrawingCodeHeavyQuadrupleDashVertical = 0x250B,  // ┋

    iTermBoxDrawingCodeLightDownAndRight = 0x250C,  // ┌
    iTermBoxDrawingCodeDownLightAndRightHeavy = 0x250D,  // ┍
    iTermBoxDrawingCodeDownHeavyAndRightLight = 0x250E,  // ┎
    iTermBoxDrawingCodeHeavyDownAndRight = 0x250F,  // ┏

    iTermBoxDrawingCodeLightDownAndLeft = 0x2510,  // ┐
    iTermBoxDrawingCodeDownLightAndLeftHeavy = 0x2511,  // ┑
    iTermBoxDrawingCodeDownHeavyAndLeftLight = 0x2512,  // ┒
    iTermBoxDrawingCodeHeavyDownAndLeft = 0x2513,  // ┓

    iTermBoxDrawingCodeLightUpAndRight = 0x2514,  // └
    iTermBoxDrawingCodeUpLightAndRightHeavy = 0x2515,  // ┕
    iTermBoxDrawingCodeUpHeavyAndRightLight = 0x2516,  // ┖
    iTermBoxDrawingCodeHeavyUpAndRight = 0x2517,  // ┗

    iTermBoxDrawingCodeLightUpAndLeft = 0x2518,  // ┘
    iTermBoxDrawingCodeUpLightAndLeftHeavy = 0x2519,  // ┙
    iTermBoxDrawingCodeUpHeavyAndLeftLight = 0x251A,  // ┚
    iTermBoxDrawingCodeHeavyUpAndLeft = 0x251B,  // ┛

    iTermBoxDrawingCodeLightVerticalAndRight = 0x251C,  // ├
    iTermBoxDrawingCodeVerticalLightAndRightHeavy = 0x251D,  // ┝
    iTermBoxDrawingCodeUpHeavyAndRightDownLight = 0x251E,  // ┞
    iTermBoxDrawingCodeDownHeavyAndRightUpLight = 0x251F,  // ┟
    iTermBoxDrawingCodeVerticalHeavyAndRightLight = 0x2520,  // ┠
    iTermBoxDrawingCodeDownLightAndRightUpHeavy = 0x2521,  // ┡
    iTermBoxDrawingCodeUpLightAndRightDownHeavy = 0x2522,  // ┢
    iTermBoxDrawingCodeHeavyVerticalAndRight = 0x2523,  // ┣

    iTermBoxDrawingCodeLightVerticalAndLeft = 0x2524,  // ┤
    iTermBoxDrawingCodeVerticalLightAndLeftHeavy = 0x2525,  // ┥
    iTermBoxDrawingCodeUpHeavyAndLeftDownLight = 0x2526,  // ┦
    iTermBoxDrawingCodeDownHeavyAndLeftUpLight = 0x2527,  // ┧
    iTermBoxDrawingCodeVerticalHeavyAndLeftLight = 0x2528,  // ┨
    iTermBoxDrawingCodeDownLightAndLeftUpHeavy = 0x2529,  // ┩
    iTermBoxDrawingCodeUpLightAndLeftDownHeavy = 0x252A,  // ┪
    iTermBoxDrawingCodeHeavyVerticalAndLeft = 0x252B,  // ┫

    iTermBoxDrawingCodeLightDownAndHorizontal = 0x252C,  // ┬
    iTermBoxDrawingCodeLeftHeavyAndRightDownLight = 0x252D,  // ┭
    iTermBoxDrawingCodeRightHeavyAndLeftDownLight = 0x252E,  // ┮
    iTermBoxDrawingCodeDownLightAndHorizontalHeavy = 0x252F,  // ┯
    iTermBoxDrawingCodeDownHeavyAndHorizontalLight = 0x2530,  // ┰
    iTermBoxDrawingCodeRightLightAndLeftDownHeavy = 0x2531,  // ┱
    iTermBoxDrawingCodeLeftLightAndRightDownHeavy = 0x2532,  // ┲
    iTermBoxDrawingCodeHeavyDownAndHorizontal = 0x2533,  // ┳

    iTermBoxDrawingCodeLightUpAndHorizontal = 0x2534,  // ┴
    iTermBoxDrawingCodeLeftHeavyAndRightUpLight = 0x2535,  // ┵
    iTermBoxDrawingCodeRightHeavyAndLeftUpLight = 0x2536,  // ┶
    iTermBoxDrawingCodeUpLightAndHorizontalHeavy = 0x2537,  // ┷
    iTermBoxDrawingCodeUpHeavyAndHorizontalLight = 0x2538,  // ┸
    iTermBoxDrawingCodeRightLightAndLeftUpHeavy = 0x2539,  // ┹
    iTermBoxDrawingCodeLeftLightAndRightUpHeavy = 0x253A,  // ┺
    iTermBoxDrawingCodeHeavyUpAndHorizontal = 0x253B,  // ┻

    iTermBoxDrawingCodeLightVerticalAndHorizontal = 0x253C,  // ┼
    iTermBoxDrawingCodeLeftHeavyAndRightVerticalLight = 0x253D,  // ┽
    iTermBoxDrawingCodeRightHeavyAndLeftVerticalLight = 0x253E,  // ┾
    iTermBoxDrawingCodeVerticalLightAndHorizontalHeavy = 0x253F,  // ┿
    iTermBoxDrawingCodeUpHeavyAndDownHorizontalLight = 0x2540,  // ╀
    iTermBoxDrawingCodeDownHeavyAndUpHorizontalLight = 0x2541,  // ╁
    iTermBoxDrawingCodeVerticalHeavyAndHorizontalLight = 0x2542,  // ╂
    iTermBoxDrawingCodeLeftUpHeavyAndRightDownLight = 0x2543,  // ╃
    iTermBoxDrawingCodeRightUpHeavyAndLeftDownLight = 0x2544,  // ╄
    iTermBoxDrawingCodeLeftDownHeavyAndRightUpLight = 0x2545,  // ╅
    iTermBoxDrawingCodeRightDownHeavyAndLeftUpLight = 0x2546,  // ╆
    iTermBoxDrawingCodeDownLightAndUpHorizontalHeavy = 0x2547,  // ╇
    iTermBoxDrawingCodeUpLightAndDownHorizontalHeavy = 0x2548,  // ╈
    iTermBoxDrawingCodeRightLightAndLeftVerticalHeavy = 0x2549,  // ╉
    iTermBoxDrawingCodeLeftLightAndRightVerticalHeavy = 0x254A,  // ╊
    iTermBoxDrawingCodeHeavyVerticalAndHorizontal = 0x254B,  // ╋

    iTermBoxDrawingCodeLightDoubleDashHorizontal = 0x254C,  // ╌
    iTermBoxDrawingCodeHeavyDoubleDashHorizontal = 0x254D,  // ╍

    iTermBoxDrawingCodeLightDoubleDashVertical = 0x254E,  // ╎
    iTermBoxDrawingCodeHeavyDoubleDashVertical = 0x254F,  // ╏

    iTermBoxDrawingCodeDoubleHorizontal = 0x2550,  // ═

    iTermBoxDrawingCodeDoubleVertical = 0x2551,  // ║

    iTermBoxDrawingCodeDownSingleAndRightDouble = 0x2552,  // ╒
    iTermBoxDrawingCodeDownDoubleAndRightSingle = 0x2553,  // ╓
    iTermBoxDrawingCodeDoubleDownAndRight = 0x2554,  // ╔

    iTermBoxDrawingCodeDownSingleAndLeftDouble = 0x2555,  // ╕
    iTermBoxDrawingCodeDownDoubleAndLeftSingle = 0x2556,  // ╖
    iTermBoxDrawingCodeDoubleDownAndLeft = 0x2557,  // ╗

    iTermBoxDrawingCodeUpSingleAndRightDouble = 0x2558,  // ╘
    iTermBoxDrawingCodeUpDoubleAndRightSingle = 0x2559,  // ╙
    iTermBoxDrawingCodeDoubleUpAndRight = 0x255A,  // ╚

    iTermBoxDrawingCodeUpSingleAndLeftDouble = 0x255B,  // ╛
    iTermBoxDrawingCodeUpDoubleAndLeftSingle = 0x255C,  // ╜
    iTermBoxDrawingCodeDoubleUpAndLeft = 0x255D,  // ╝

    iTermBoxDrawingCodeVerticalSingleAndRightDouble = 0x255E,  // ╞
    iTermBoxDrawingCodeVerticalDoubleAndRightSingle = 0x255F,  // ╟
    iTermBoxDrawingCodeDoubleVerticalAndRight = 0x2560,  // ╠

    iTermBoxDrawingCodeVerticalSingleAndLeftDouble = 0x2561,  // ╡
    iTermBoxDrawingCodeVerticalDoubleAndLeftSingle = 0x2562,  // ╢
    iTermBoxDrawingCodeDoubleVerticalAndLeft = 0x2563,  // ╣

    iTermBoxDrawingCodeDownSingleAndHorizontalDouble = 0x2564,  // ╤
    iTermBoxDrawingCodeDownDoubleAndHorizontalSingle = 0x2565,  // ╥
    iTermBoxDrawingCodeDoubleDownAndHorizontal = 0x2566,  // ╦

    iTermBoxDrawingCodeUpSingleAndHorizontalDouble = 0x2567,  // ╧
    iTermBoxDrawingCodeUpDoubleAndHorizontalSingle = 0x2568,  // ╨
    iTermBoxDrawingCodeDoubleUpAndHorizontal = 0x2569,  // ╩

    iTermBoxDrawingCodeVerticalSingleAndHorizontalDouble = 0x256A,  // ╪
    iTermBoxDrawingCodeVerticalDoubleAndHorizontalSingle = 0x256B,  // ╫
    iTermBoxDrawingCodeDoubleVerticalAndHorizontal = 0x256C,  // ╬

    iTermBoxDrawingCodeLightArcDownAndRight = 0x256D,  // ╭
    iTermBoxDrawingCodeLightArcDownAndLeft = 0x256E,  // ╮
    iTermBoxDrawingCodeLightArcUpAndLeft = 0x256F,  // ╯
    iTermBoxDrawingCodeLightArcUpAndRight = 0x2570,  // ╰

    iTermBoxDrawingCodeLightDiagonalUpperRightToLowerLeft = 0x2571,  // ╱

    iTermBoxDrawingCodeLightDiagonalUpperLeftToLowerRight = 0x2572,  // ╲

    iTermBoxDrawingCodeLightDiagonalCross = 0x2573,  // ╳

    iTermBoxDrawingCodeLightLeft = 0x2574,  // ╴

    iTermBoxDrawingCodeLightUp = 0x2575,  // ╵

    iTermBoxDrawingCodeLightRight = 0x2576,  // ╶

    iTermBoxDrawingCodeLightDown = 0x2577,  // ╷

    iTermBoxDrawingCodeHeavyLeft = 0x2578,  // ╸

    iTermBoxDrawingCodeHeavyUp = 0x2579,  // ╹

    iTermBoxDrawingCodeHeavyRight = 0x257A,  // ╺

    iTermBoxDrawingCodeHeavyDown = 0x257B,  // ╻

    iTermBoxDrawingCodeLightLeftAndHeavyRight = 0x257C,  // ╼

    iTermBoxDrawingCodeLightUpAndHeavyDown = 0x257D,  // ╽

    iTermBoxDrawingCodeHeavyLeftAndLightRight = 0x257E,  // ╾

    iTermBoxDrawingCodeHeavyUpAndLightDown = 0x257F,  // ╿


    iTermUpperHalfBlock                               = 0x2580, // ▀
    iTermLowerOneEighthBlock                          = 0x2581, // ▁
    iTermLowerOneQuarterBlock                         = 0x2582, // ▂
    iTermLowerThreeEighthsBlock                       = 0x2583, // ▃
    iTermLowerHalfBlock                               = 0x2584, // ▄
    iTermLowerFiveEighthsBlock                        = 0x2585, // ▅
    iTermLowerThreeQuartersBlock                      = 0x2586, // ▆
    iTermLowerSevenEighthsBlock                       = 0x2587, // ▇
    iTermFullBlock                                    = 0x2588, // █
    iTermLeftSevenEighthsBlock                        = 0x2589, // ▉
    iTermLeftThreeQuartersBlock                       = 0x258A, // ▊
    iTermLeftFiveEighthsBlock                         = 0x258B, // ▋
    iTermLeftHalfBlock                                = 0x258C, // ▌
    iTermLeftThreeEighthsBlock                        = 0x258D, // ▍
    iTermLeftOneQuarterBlock                          = 0x258E, // ▎
    iTermLeftOneEighthBlock                           = 0x258F, // ▏
    iTermRightHalfBlock                               = 0x2590, // ▐
    iTermLightShade                                   = 0x2591, // ░
    iTermMediumShade                                  = 0x2592, // ▒
    iTermDarkShade                                    = 0x2593, // ▓
    iTermUpperOneEighthBlock                          = 0x2594, // ▔
    iTermRightOneEighthBlock                          = 0x2595, // ▕
    iTermQuadrantLowerLeft                            = 0x2596, // ▖
    iTermQuadrantLowerRight                           = 0x2597, // ▗
    iTermQuadrantUpperLeft                            = 0x2598, // ▘
    iTermQuadrantUpperLeftAndLowerLeftAndLowerRight   = 0x2599, // ▙
    iTermQuadrantUpperLeftAndLowerRight               = 0x259A, // ▚
    iTermQuadrantUpperLeftAndUpperRightAndLowerLeft   = 0x259B, // ▛
    iTermQuadrantUpperLeftAndUpperRightAndLowerRight  = 0x259C, // ▜
    iTermQuadrantUpperRight                           = 0x259D, // ▝
    iTermQuadrantUpperRightAndLowerLeft               = 0x259E, // ▞
    iTermQuadrantUpperRightAndLowerLeftAndLowerRight  = 0x259F, // ▟
    // NOTE: If you add more block characters update two methods in iTermBoxDrawingBezierCurveFactory
};

// Defines a mapping from ascii characters to their Unicode graphical equivalent. Used in line-
// drawing mode.
extern const unichar charmap[256];
const unichar * _Nonnull GetASCIIToUnicodeBoxTable(void);

