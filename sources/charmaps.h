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

    iTermBlackLowerRightTriangle                      = 0x25e2,  // ◢
    iTermBlackLowerLeftTriangle                       = 0x25e3,  // ◣
    iTermBlackUpperLeftTriangle                       = 0x25e4,  // ◤
    iTermBlackUpperRightTriangle                      = 0x25e5,  // ◥
    iTermUpperLeftTriangle                            = 0x25f8,  // ◸
    iTermUpperRightTriangle                           = 0x25f9,  // ◹
    iTermLowerLeftTriangle                            = 0x25fa,  // ◺
    iTermLowerRightTriangle                           = 0x25ff,  // ◿
    // / NOTE: If you add more block characters update two methods in iTermBoxDrawingBezierCurveFactory
};

typedef NS_ENUM(UTF32Char, iTermExtendedBoxDrawingCode) {
    iTermBlockSextant1 = 0x1FB00,  // 🬀
    iTermBlockSextant2 = 0x1FB01,  // 🬁
    iTermBlockSextant12 = 0x1FB02,  // 🬂
    iTermBlockSextant3 = 0x1FB03,  // 🬃
    iTermBlockSextant13 = 0x1FB04,  // 🬄
    iTermBlockSextant23 = 0x1FB05,  // 🬅
    iTermBlockSextant123 = 0x1FB06,  // 🬆
    iTermBlockSextant4 = 0x1FB07,  // 🬇
    iTermBlockSextant14 = 0x1FB08,  // 🬈
    iTermBlockSextant24 = 0x1FB09,  // 🬉
    iTermBlockSextant124 = 0x1FB0a,  // 🬊
    iTermBlockSextant34 = 0x1FB0b,  // 🬋
    iTermBlockSextant134 = 0x1FB0c,  // 🬌
    iTermBlockSextant234 = 0x1FB0d,  // 🬍
    iTermBlockSextant1234 = 0x1FB0e,  // 🬎
    iTermBlockSextant5 = 0x1FB0f,  // 🬏
    iTermBlockSextant15 = 0x1FB10,  // 🬐
    iTermBlockSextant25 = 0x1FB11,  // 🬑
    iTermBlockSextant125 = 0x1FB12,  // 🬒
    iTermBlockSextant35 = 0x1FB13,  // 🬓
    iTermBlockSextant235 = 0x1FB14,  // 🬔
    iTermBlockSextant1235 = 0x1FB15,  // 🬕
    iTermBlockSextant45 = 0x1FB16,  // 🬖
    iTermBlockSextant145 = 0x1FB17,  // 🬗
    iTermBlockSextant245 = 0x1FB18,  // 🬘
    iTermBlockSextant1245 = 0x1FB19,  // 🬙
    iTermBlockSextant345 = 0x1FB1a,  // 🬚
    iTermBlockSextant1345 = 0x1FB1b,  // 🬛
    iTermBlockSextant2345 = 0x1FB1c,  // 🬜
    iTermBlockSextant12345 = 0x1FB1d,  // 🬝
    iTermBlockSextant6 = 0x1FB1e,  // 🬞
    iTermBlockSextant16 = 0x1FB1f,  // 🬟
    iTermBlockSextant26 = 0x1FB20,  // 🬠
    iTermBlockSextant126 = 0x1FB21,  // 🬡
    iTermBlockSextant36 = 0x1FB22,  // 🬢
    iTermBlockSextant136 = 0x1FB23,  // 🬣
    iTermBlockSextant236 = 0x1FB24,  // 🬤
    iTermBlockSextant1236 = 0x1FB25,  // 🬥
    iTermBlockSextant46 = 0x1FB26,  // 🬦
    iTermBlockSextant146 = 0x1FB27,  // 🬧
    iTermBlockSextant1246 = 0x1FB28,  // 🬨
    iTermBlockSextant346 = 0x1FB29,  // 🬩
    iTermBlockSextant1346 = 0x1FB2a,  // 🬪
    iTermBlockSextant2346 = 0x1FB2b,  // 🬫
    iTermBlockSextant12346 = 0x1FB2c,  // 🬬
    iTermBlockSextant56 = 0x1FB2d,  // 🬭
    iTermBlockSextant156 = 0x1FB2e,  // 🬮
    iTermBlockSextant256 = 0x1FB2f,  // 🬯
    iTermBlockSextant1256 = 0x1FB30,  // 🬰
    iTermBlockSextant356 = 0x1FB31,  // 🬱
    iTermBlockSextant1356 = 0x1FB32,  // 🬲
    iTermBlockSextant2356 = 0x1FB33,  // 🬳
    iTermBlockSextant12356 = 0x1FB34,  // 🬴
    iTermBlockSextant456 = 0x1FB35,  // 🬵
    iTermBlockSextant1456 = 0x1FB36,  // 🬶
    iTermBlockSextant2456 = 0x1FB37,  // 🬷
    iTermBlockSextant12456 = 0x1FB38,  // 🬸
    iTermBlockSextant3456 = 0x1FB39,  // 🬹
    iTermBlockSextant13456 = 0x1FB3a,  // 🬺
    iTermBlockSextant23456 = 0x1FB3b,  // 🬻

    iTermLowerLeftBlockDiagonalLowerMiddleLeftToLowerCentre = 0x1FB3C,  // 🬼
    iTermLowerLeftBlockDiagonalLowerMiddleLeftToLowerRight = 0x1FB3D,  // 🬽
    iTermLowerLeftBlockDiagonalUpperMiddleLeftToLowerCentre = 0x1FB3E,  // 🬾
    iTermLowerLeftBlockDiagonalUpperMiddleLeftToLowerRight = 0x1FB3F,  // 🬿
    iTermLowerLeftBlockDiagonalUpperLeftToLowerCentre = 0x1FB40,  // 🭀
    iTermLowerRightBlockDiagonalUpperMiddleLeftToUpperCentre = 0x1FB41,  // 🭁
    iTermLowerRightBlockDiagonalUpperMiddleLeftToUpperRight = 0x1FB42,  // 🭂
    iTermLowerRightBlockDiagonalLowerMiddleLeftToUpperCentre = 0x1FB43,  // 🭃
    iTermLowerRightBlockDiagonalLowerMiddleLeftToUpperRight = 0x1FB44,  // 🭄
    iTermLowerRightBlockDiagonalLowerLeftToUpperCentre = 0x1FB45,  // 🭅
    iTermLowerRightBlockDiagonalLowerMiddleLeftToUpperMiddleRight = 0x1FB46,  // 🭆
    iTermLowerRightBlockDiagonalLowerCentreToLowerMiddleRight = 0x1FB47,  // 🭇
    iTermLowerRightBlockDiagonalLowerLeftToLowerMiddleRight = 0x1FB48,  // 🭈
    iTermLowerRightBlockDiagonalLowerCentreToUpperMiddleRight = 0x1FB49,  // 🭉
    iTermLowerRightBlockDiagonalLowerLeftToUpperMiddleRight = 0x1FB4A,  // 🭊
    iTermLowerRightBlockDiagonalLowerCentreToUpperRight = 0x1FB4B,  // 🭋
    iTermLowerLeftBlockDiagonalUpperCentreToUpperMiddleRight = 0x1FB4C,  // 🭌
    iTermLowerLeftBlockDiagonalUpperLeftToUpperMiddleRight = 0x1FB4D,  // 🭍
    iTermLowerLeftBlockDiagonalUpperCentreToLowerMiddleRight = 0x1FB4E,  // 🭎
    iTermLowerLeftBlockDiagonalUpperLeftToLowerMiddleRight = 0x1FB4F,  // 🭏
    iTermLowerLeftBlockDiagonalUpperCentreToLowerRight = 0x1FB50,  // 🭐
    iTermLowerLeftBlockDiagonalUpperMiddleLeftToLowerMiddleRight = 0x1FB51,  // 🭑
    iTermUpperRightBlockDiagonalLowerMiddleLeftToLowerCentre = 0x1FB52,  // 🭒
    iTermUpperRightBlockDiagonalLowerMiddleLeftToLowerRight = 0x1FB53,  // 🭓
    iTermUpperRightBlockDiagonalUpperMiddleLeftToLowerCentre = 0x1FB54,  // 🭔
    iTermUpperRightBlockDiagonalUpperMiddleLeftToLowerRight = 0x1FB55,  // 🭕
    iTermUpperRightBlockDiagonalUpperLeftToLowerCentre = 0x1FB56,  // 🭖
    iTermUpperLeftBlockDiagonalUpperMiddleLeftToUpperCentre = 0x1FB57,  // 🭗
    iTermUpperLeftBlockDiagonalUpperMiddleLeftToUpperRight = 0x1FB58,  // 🭘
    iTermUpperLeftBlockDiagonalLowerMiddleLeftToUpperCentre = 0x1FB59,  // 🭙
    iTermUpperLeftBlockDiagonalLowerMiddleLeftToUpperRight = 0x1FB5A,  // 🭚
    iTermUpperLeftBlockDiagonalLowerLeftToUpperCentre = 0x1FB5B,  // 🭛
    iTermUpperLeftBlockDiagonalLowerMiddleLeftToUpperMiddleRight = 0x1FB5C,  // 🭜
    iTermUpperLeftBlockDiagonalLowerCentreToLowerMiddleRight = 0x1FB5D,  // 🭝
    iTermUpperLeftBlockDiagonalLowerLeftToLowerMiddleRight = 0x1FB5E,  // 🭞
    iTermUpperLeftBlockDiagonalLowerCentreToUpperMiddleRight = 0x1FB5F,  // 🭟
    iTermUpperLeftBlockDiagonalLowerLeftToUpperMiddleRight = 0x1FB60,  // 🭠
    iTermUpperLeftBlockDiagonalLowerCentreToUpperRight = 0x1FB61,  // 🭡
    iTermUpperRightBlockDiagonalUpperCentreToUpperMiddleRight = 0x1FB62,  // 🭢
    iTermUpperRightBlockDiagonalUpperLeftToUpperMiddleRight = 0x1FB63,  // 🭣
    iTermUpperRightBlockDiagonalUpperCentreToLowerMiddleRight = 0x1FB64,  // 🭤
    iTermUpperRightBlockDiagonalUpperLeftToLowerMiddleRight = 0x1FB65,  // 🭥
    iTermUpperRightBlockDiagonalUpperCentreToLowerRight = 0x1FB66,  // 🭦
    iTermUpperRightBlockDiagonalUpperMiddleLeftToLowerMiddleRight = 0x1FB67,  // 🭧
    iTermUpperAndRightAndLowerTriangularThreeQuartersBlock = 0x1FB68,  // 🭨
    iTermLeftAndLowerAndRightTriangularThreeQuartersBlock = 0x1FB69,  // 🭩
    iTermUpperAndLeftAndLowerTriangularThreeQuartersBlock = 0x1FB6A,  // 🭪
    iTermLeftAndUpperAndRightTriangularThreeQuartersBlock = 0x1FB6B,  // 🭫
    iTermLeftTriangularOneQuarterBlock = 0x1FB6C,  // 🭬
    iTermUpperTriangularOneQuarterBlock = 0x1FB6D,  // 🭭
    iTermRightTriangularOneQuarterBlock = 0x1FB6E,  // 🭮
    iTermLowerTriangularOneQuarterBlock = 0x1FB6F,  // 🭯
    // / NOTE: If you add more block characters update two methods in iTermBoxDrawingBezierCurveFactory
};

// Defines a mapping from ascii characters to their Unicode graphical equivalent. Used in line-
// drawing mode.
extern const unichar charmap[256];
const unichar * _Nonnull GetASCIIToUnicodeBoxTable(void);

