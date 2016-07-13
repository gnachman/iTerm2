/* Derived from linux/drivers/char/consolemap.c, GNU GPL:ed */

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
*/

#define iTermBoxDrawingCodeMin 0x2500
#define iTermBoxDrawingCodeMax 0x257f

NS_ENUM(unichar, iTermBoxDrawingCode) {
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
};

// Defines a mapping from ascii characters to their Unicode graphical equivalent. Used in line-
// drawing mode.
static const unichar charmap[256]={
    0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007,
    0x0008, 0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x000e, 0x000f,
    0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016, 0x0017,
    0x0018, 0x0019, 0x001a, 0x001b, 0x001c, 0x001d, 0x001e, 0x001f,
    0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027,
    0x0028, 0x0029, 0x002a, 0x002b, 0x002c, 0x002d, 0x002e, 0x002f,
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037,
    0x0038, 0x0039, 0x003a, 0x003b, 0x003c, 0x003d, 0x003e, 0x003f,
    0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047,
    0x0048, 0x0049, 0x004a, 0x004b, 0x004c, 0x004d, 0x004e, 0x004f,
    0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057,
    0x0058, 0x0059, 0x005a, 0x005b, 0x005c, 0x005d, 0x005e, 0x00a0,
    0x25c6, 0x2592, 0x2409, 0x240c, 0x240d, 0x240a, 0x00b0, 0x00b1,
    0x2424, 0x240b,
    iTermBoxDrawingCodeLightUpAndLeft,
    iTermBoxDrawingCodeLightDownAndLeft,
    iTermBoxDrawingCodeLightDownAndRight,
    iTermBoxDrawingCodeLightUpAndRight,
    iTermBoxDrawingCodeLightVerticalAndHorizontal,
    0x23ba, 0x23bb,
    iTermBoxDrawingCodeLightHorizontal,
    0x23bc, 0x23bd,
    iTermBoxDrawingCodeLightVerticalAndRight,
    iTermBoxDrawingCodeLightVerticalAndLeft,
    iTermBoxDrawingCodeLightUpAndHorizontal,
    iTermBoxDrawingCodeLightDownAndHorizontal,
    iTermBoxDrawingCodeLightVertical,
            0x2264, 0x2265, 0x03c0, 0x2260, 0x00a3, 0x00b7, 0x007f,
    0x0080, 0x0081, 0x0082, 0x0083, 0x0084, 0x0085, 0x0086, 0x0087,
    0x0088, 0x0089, 0x008a, 0x008b, 0x008c, 0x008d, 0x008e, 0x008f,
    0x0090, 0x0091, 0x0092, 0x0093, 0x0094, 0x0095, 0x0096, 0x0097,
    0x0098, 0x0099, 0x009a, 0x009b, 0x009c, 0x009d, 0x009e, 0x009f,
    0x00a0, 0x00a1, 0x00a2, 0x00a3, 0x00a4, 0x00a5, 0x00a6, 0x00a7,
    0x00a8, 0x00a9, 0x00aa, 0x00ab, 0x00ac, 0x00ad, 0x00ae, 0x00af,
    0x00b0, 0x00b1, 0x00b2, 0x00b3, 0x00b4, 0x00b5, 0x00b6, 0x00b7,
    0x00b8, 0x00b9, 0x00ba, 0x00bb, 0x00bc, 0x00bd, 0x00be, 0x00bf,
    0x00c0, 0x00c1, 0x00c2, 0x00c3, 0x00c4, 0x00c5, 0x00c6, 0x00c7,
    0x00c8, 0x00c9, 0x00ca, 0x00cb, 0x00cc, 0x00cd, 0x00ce, 0x00cf,
    0x00d0, 0x00d1, 0x00d2, 0x00d3, 0x00d4, 0x00d5, 0x00d6, 0x00d7,
    0x00d8, 0x00d9, 0x00da, 0x00db, 0x00dc, 0x00dd, 0x00de, 0x00df,
    0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6, 0x00e7,
    0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee, 0x00ef,
    0x00f0, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6, 0x00f7,
    0x00f8, 0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x00fd, 0x00fe, 0x00ff
};

