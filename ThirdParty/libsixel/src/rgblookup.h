/* C code produced by gperf version 3.0.3 */
/* Command-line: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/gperf -C -N lookup_rgb --ignore-case rgblookup.gperf  */
/* Computed positions: -k'1,3,5-9,12-15,$' */

#if !((' ' == 32) && ('!' == 33) && ('"' == 34) && ('#' == 35) \
      && ('%' == 37) && ('&' == 38) && ('\'' == 39) && ('(' == 40) \
      && (')' == 41) && ('*' == 42) && ('+' == 43) && (',' == 44) \
      && ('-' == 45) && ('.' == 46) && ('/' == 47) && ('0' == 48) \
      && ('1' == 49) && ('2' == 50) && ('3' == 51) && ('4' == 52) \
      && ('5' == 53) && ('6' == 54) && ('7' == 55) && ('8' == 56) \
      && ('9' == 57) && (':' == 58) && (';' == 59) && ('<' == 60) \
      && ('=' == 61) && ('>' == 62) && ('?' == 63) && ('A' == 65) \
      && ('B' == 66) && ('C' == 67) && ('D' == 68) && ('E' == 69) \
      && ('F' == 70) && ('G' == 71) && ('H' == 72) && ('I' == 73) \
      && ('J' == 74) && ('K' == 75) && ('L' == 76) && ('M' == 77) \
      && ('N' == 78) && ('O' == 79) && ('P' == 80) && ('Q' == 81) \
      && ('R' == 82) && ('S' == 83) && ('T' == 84) && ('U' == 85) \
      && ('V' == 86) && ('W' == 87) && ('X' == 88) && ('Y' == 89) \
      && ('Z' == 90) && ('[' == 91) && ('\\' == 92) && (']' == 93) \
      && ('^' == 94) && ('_' == 95) && ('a' == 97) && ('b' == 98) \
      && ('c' == 99) && ('d' == 100) && ('e' == 101) && ('f' == 102) \
      && ('g' == 103) && ('h' == 104) && ('i' == 105) && ('j' == 106) \
      && ('k' == 107) && ('l' == 108) && ('m' == 109) && ('n' == 110) \
      && ('o' == 111) && ('p' == 112) && ('q' == 113) && ('r' == 114) \
      && ('s' == 115) && ('t' == 116) && ('u' == 117) && ('v' == 118) \
      && ('w' == 119) && ('x' == 120) && ('y' == 121) && ('z' == 122) \
      && ('{' == 123) && ('|' == 124) && ('}' == 125) && ('~' == 126))
/* The character set is not based on ISO-646.  */
error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gnu-gperf@gnu.org>."
#endif

#line 2 "rgblookup.gperf"
struct color {
    char *name;
    unsigned char r;
    unsigned char g;
    unsigned char b;
};

#define TOTAL_KEYWORDS 752
#define MIN_WORD_LENGTH 3
#define MAX_WORD_LENGTH 22
#define MIN_HASH_VALUE 3
#define MAX_HASH_VALUE 5574
/* maximum key range = 5572, duplicates = 0 */

#ifndef GPERF_DOWNCASE
#define GPERF_DOWNCASE 1
static unsigned char gperf_downcase[256] =
{
    0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,
    15,  16,  17,  18,  19,  20,  21,  22,  23,  24,  25,  26,  27,  28,  29,
    30,  31,  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,
    45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,
    60,  61,  62,  63,  64,  97,  98,  99, 100, 101, 102, 103, 104, 105, 106,
    107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
    122,  91,  92,  93,  94,  95,  96,  97,  98,  99, 100, 101, 102, 103, 104,
    105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
    120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134,
    135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
    150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164,
    165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179,
    180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194,
    195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209,
    210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
    225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
    240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254,
    255
};
#endif

#ifndef GPERF_CASE_STRCMP
#define GPERF_CASE_STRCMP 1
static int
gperf_case_strcmp (s1, s2)
register const char *s1;
register const char *s2;
{
    for (;;)
    {
        unsigned char c1 = gperf_downcase[(unsigned char)*s1++];
        unsigned char c2 = gperf_downcase[(unsigned char)*s2++];
        if (c1 != 0 && c1 == c2)
            continue;
        return (int)c1 - (int)c2;
    }
}
#endif

#ifdef __GNUC__
__inline
#else
#ifdef __cplusplus
inline
#endif
#endif
static unsigned int
hash (str, len)
register const char *str;
register unsigned int len;
{
    static const unsigned short asso_values[] =
    {
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575,  520, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,  920,   25,
        20,    5,    0, 1007,  841,   16,  915,  840, 5575, 5575,
        5575, 5575, 5575, 5575, 5575,   80,    5,  980,    0,    0,
        55,    0,  670,  673,    0,  395,  215,  190,  160,  100,
        1015,  145,    0,    0,  155,  325,  740,  831, 5575,  265,
        5575, 5575, 5575, 5575, 5575, 5575, 5575,   80,    5,  980,
        0,    0,   55,    0,  670,  673,    0,  395,  215,  190,
        160,  100, 1015,  145,    0,    0,  155,  325,  740,  831,
        5575,  265, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575, 5575,
        5575, 5575, 5575, 5575, 5575, 5575
    };
    register unsigned int hval = len;

    switch (hval)
    {
    default:
        hval += asso_values[(unsigned char)str[14]];
    /*FALLTHROUGH*/
    case 14:
        hval += asso_values[(unsigned char)str[13]];
    /*FALLTHROUGH*/
    case 13:
        hval += asso_values[(unsigned char)str[12]];
    /*FALLTHROUGH*/
    case 12:
        hval += asso_values[(unsigned char)str[11]];
    /*FALLTHROUGH*/
    case 11:
    case 10:
    case 9:
        hval += asso_values[(unsigned char)str[8]];
    /*FALLTHROUGH*/
    case 8:
        hval += asso_values[(unsigned char)str[7]];
    /*FALLTHROUGH*/
    case 7:
        hval += asso_values[(unsigned char)str[6]];
    /*FALLTHROUGH*/
    case 6:
        hval += asso_values[(unsigned char)str[5]];
    /*FALLTHROUGH*/
    case 5:
        hval += asso_values[(unsigned char)str[4]];
    /*FALLTHROUGH*/
    case 4:
    case 3:
        hval += asso_values[(unsigned char)str[2]];
    /*FALLTHROUGH*/
    case 2:
    case 1:
        hval += asso_values[(unsigned char)str[0]];
        break;
    }
    return hval + asso_values[(unsigned char)str[len - 1]];
}

const struct color *
lookup_rgb (str, len)
register const char *str;
register unsigned int len;
{
    static const struct color wordlist[] =
    {
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 202 "rgblookup.gperf"
        {"red", 0xff, 0x00, 0x00},
#line 484 "rgblookup.gperf"
        {"red4", 0x8b, 0x00, 0x00},
#line 554 "rgblookup.gperf"
        {"grey4", 0x0a, 0x0a, 0x0a},
#line 634 "rgblookup.gperf"
        {"grey44", 0x70, 0x70, 0x70},
#line 758 "rgblookup.gperf"
        {"darkred", 0x8b, 0x00, 0x00},
        {"", 0, 0, 0},
#line 483 "rgblookup.gperf"
        {"red3", 0xcd, 0x00, 0x00},
        {"", 0, 0, 0},
#line 614 "rgblookup.gperf"
        {"grey34", 0x57, 0x57, 0x57},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 552 "rgblookup.gperf"
        {"grey3", 0x08, 0x08, 0x08},
#line 632 "rgblookup.gperf"
        {"grey43", 0x6e, 0x6e, 0x6e},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 612 "rgblookup.gperf"
        {"grey33", 0x54, 0x54, 0x54},
#line 694 "rgblookup.gperf"
        {"grey74", 0xbd, 0xbd, 0xbd},
        {"", 0, 0, 0},
#line 482 "rgblookup.gperf"
        {"red2", 0xee, 0x00, 0x00},
        {"", 0, 0, 0},
#line 594 "rgblookup.gperf"
        {"grey24", 0x3d, 0x3d, 0x3d},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 481 "rgblookup.gperf"
        {"red1", 0xff, 0x00, 0x00},
        {"", 0, 0, 0},
#line 574 "rgblookup.gperf"
        {"grey14", 0x24, 0x24, 0x24},
#line 692 "rgblookup.gperf"
        {"grey73", 0xba, 0xba, 0xba},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 592 "rgblookup.gperf"
        {"grey23", 0x3b, 0x3b, 0x3b},
#line 560 "rgblookup.gperf"
        {"grey7", 0x12, 0x12, 0x12},
#line 640 "rgblookup.gperf"
        {"grey47", 0x78, 0x78, 0x78},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 572 "rgblookup.gperf"
        {"grey13", 0x21, 0x21, 0x21},
        {"", 0, 0, 0},
#line 620 "rgblookup.gperf"
        {"grey37", 0x5e, 0x5e, 0x5e},
        {"", 0, 0, 0},
#line 550 "rgblookup.gperf"
        {"grey2", 0x05, 0x05, 0x05},
#line 630 "rgblookup.gperf"
        {"grey42", 0x6b, 0x6b, 0x6b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 610 "rgblookup.gperf"
        {"grey32", 0x52, 0x52, 0x52},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 700 "rgblookup.gperf"
        {"grey77", 0xc4, 0xc4, 0xc4},
#line 548 "rgblookup.gperf"
        {"grey1", 0x03, 0x03, 0x03},
#line 628 "rgblookup.gperf"
        {"grey41", 0x69, 0x69, 0x69},
        {"", 0, 0, 0},
#line 600 "rgblookup.gperf"
        {"grey27", 0x45, 0x45, 0x45},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 608 "rgblookup.gperf"
        {"grey31", 0x4f, 0x4f, 0x4f},
#line 690 "rgblookup.gperf"
        {"grey72", 0xb8, 0xb8, 0xb8},
#line 580 "rgblookup.gperf"
        {"grey17", 0x2b, 0x2b, 0x2b},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 590 "rgblookup.gperf"
        {"grey22", 0x38, 0x38, 0x38},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 570 "rgblookup.gperf"
        {"grey12", 0x1f, 0x1f, 0x1f},
#line 688 "rgblookup.gperf"
        {"grey71", 0xb5, 0xb5, 0xb5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 588 "rgblookup.gperf"
        {"grey21", 0x36, 0x36, 0x36},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 568 "rgblookup.gperf"
        {"grey11", 0x1c, 0x1c, 0x1c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 553 "rgblookup.gperf"
        {"gray4", 0x0a, 0x0a, 0x0a},
#line 633 "rgblookup.gperf"
        {"gray44", 0x70, 0x70, 0x70},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 613 "rgblookup.gperf"
        {"gray34", 0x57, 0x57, 0x57},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 551 "rgblookup.gperf"
        {"gray3", 0x08, 0x08, 0x08},
#line 631 "rgblookup.gperf"
        {"gray43", 0x6e, 0x6e, 0x6e},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 611 "rgblookup.gperf"
        {"gray33", 0x54, 0x54, 0x54},
#line 693 "rgblookup.gperf"
        {"gray74", 0xbd, 0xbd, 0xbd},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 236 "rgblookup.gperf"
        {"snow4", 0x8b, 0x89, 0x89},
#line 593 "rgblookup.gperf"
        {"gray24", 0x3d, 0x3d, 0x3d},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 573 "rgblookup.gperf"
        {"gray14", 0x24, 0x24, 0x24},
#line 691 "rgblookup.gperf"
        {"gray73", 0xba, 0xba, 0xba},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 235 "rgblookup.gperf"
        {"snow3", 0xcd, 0xc9, 0xc9},
#line 591 "rgblookup.gperf"
        {"gray23", 0x3b, 0x3b, 0x3b},
#line 559 "rgblookup.gperf"
        {"gray7", 0x12, 0x12, 0x12},
#line 639 "rgblookup.gperf"
        {"gray47", 0x78, 0x78, 0x78},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 571 "rgblookup.gperf"
        {"gray13", 0x21, 0x21, 0x21},
        {"", 0, 0, 0},
#line 619 "rgblookup.gperf"
        {"gray37", 0x5e, 0x5e, 0x5e},
        {"", 0, 0, 0},
#line 549 "rgblookup.gperf"
        {"gray2", 0x05, 0x05, 0x05},
#line 629 "rgblookup.gperf"
        {"gray42", 0x6b, 0x6b, 0x6b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 609 "rgblookup.gperf"
        {"gray32", 0x52, 0x52, 0x52},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 699 "rgblookup.gperf"
        {"gray77", 0xc4, 0xc4, 0xc4},
#line 547 "rgblookup.gperf"
        {"gray1", 0x03, 0x03, 0x03},
#line 627 "rgblookup.gperf"
        {"gray41", 0x69, 0x69, 0x69},
        {"", 0, 0, 0},
#line 599 "rgblookup.gperf"
        {"gray27", 0x45, 0x45, 0x45},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 607 "rgblookup.gperf"
        {"gray31", 0x4f, 0x4f, 0x4f},
#line 689 "rgblookup.gperf"
        {"gray72", 0xb8, 0xb8, 0xb8},
#line 579 "rgblookup.gperf"
        {"gray17", 0x2b, 0x2b, 0x2b},
        {"", 0, 0, 0},
#line 234 "rgblookup.gperf"
        {"snow2", 0xee, 0xe9, 0xe9},
#line 589 "rgblookup.gperf"
        {"gray22", 0x38, 0x38, 0x38},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 569 "rgblookup.gperf"
        {"gray12", 0x1f, 0x1f, 0x1f},
#line 687 "rgblookup.gperf"
        {"gray71", 0xb5, 0xb5, 0xb5},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 233 "rgblookup.gperf"
        {"snow1", 0xff, 0xfa, 0xfa},
#line 587 "rgblookup.gperf"
        {"gray21", 0x36, 0x36, 0x36},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 567 "rgblookup.gperf"
        {"gray11", 0x1c, 0x1c, 0x1c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 376 "rgblookup.gperf"
        {"green4", 0x00, 0x8b, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 372 "rgblookup.gperf"
        {"springgreen4", 0x00, 0x8b, 0x45},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 375 "rgblookup.gperf"
        {"green3", 0x00, 0xcd, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 371 "rgblookup.gperf"
        {"springgreen3", 0x00, 0xcd, 0x66},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 193 "rgblookup.gperf"
        {"orange", 0xff, 0xa5, 0x00},
#line 464 "rgblookup.gperf"
        {"orange4", 0x8b, 0x5a, 0x00},
        {"", 0, 0, 0},
#line 201 "rgblookup.gperf"
        {"orangered", 0xff, 0x45, 0x00},
#line 480 "rgblookup.gperf"
        {"orangered4", 0x8b, 0x25, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 479 "rgblookup.gperf"
        {"orangered3", 0xcd, 0x37, 0x00},
        {"", 0, 0, 0},
#line 463 "rgblookup.gperf"
        {"orange3", 0xcd, 0x85, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 374 "rgblookup.gperf"
        {"green2", 0x00, 0xee, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 478 "rgblookup.gperf"
        {"orangered2", 0xee, 0x40, 0x00},
        {"", 0, 0, 0},
#line 370 "rgblookup.gperf"
        {"springgreen2", 0x00, 0xee, 0x76},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 477 "rgblookup.gperf"
        {"orangered1", 0xff, 0x45, 0x00},
#line 373 "rgblookup.gperf"
        {"green1", 0x00, 0xff, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 165 "rgblookup.gperf"
        {"gold", 0xff, 0xd7, 0x00},
#line 408 "rgblookup.gperf"
        {"gold4", 0x8b, 0x75, 0x00},
        {"", 0, 0, 0},
#line 369 "rgblookup.gperf"
        {"springgreen1", 0x00, 0xff, 0x7f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 462 "rgblookup.gperf"
        {"orange2", 0xee, 0x9a, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 407 "rgblookup.gperf"
        {"gold3", 0xcd, 0xad, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 461 "rgblookup.gperf"
        {"orange1", 0xff, 0xa5, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 428 "rgblookup.gperf"
        {"sienna4", 0x8b, 0x47, 0x26},
        {"", 0, 0, 0},
#line 364 "rgblookup.gperf"
        {"seagreen4", 0x2e, 0x8b, 0x57},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 360 "rgblookup.gperf"
        {"darkseagreen4", 0x69, 0x8b, 0x69},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 427 "rgblookup.gperf"
        {"sienna3", 0xcd, 0x68, 0x39},
        {"", 0, 0, 0},
#line 363 "rgblookup.gperf"
        {"seagreen3", 0x43, 0xcd, 0x80},
#line 406 "rgblookup.gperf"
        {"gold2", 0xee, 0xc9, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 359 "rgblookup.gperf"
        {"darkseagreen3", 0x9b, 0xcd, 0x9b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 67 "rgblookup.gperf"
        {"grey", 0xbe, 0xbe, 0xbe},
#line 405 "rgblookup.gperf"
        {"gold1", 0xff, 0xd7, 0x00},
#line 452 "rgblookup.gperf"
        {"brown4", 0x8b, 0x23, 0x23},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 451 "rgblookup.gperf"
        {"brown3", 0xcd, 0x33, 0x33},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 426 "rgblookup.gperf"
        {"sienna2", 0xee, 0x79, 0x42},
        {"", 0, 0, 0},
#line 362 "rgblookup.gperf"
        {"seagreen2", 0x4e, 0xee, 0x94},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 358 "rgblookup.gperf"
        {"darkseagreen2", 0xb4, 0xee, 0xb4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 425 "rgblookup.gperf"
        {"sienna1", 0xff, 0x82, 0x47},
        {"", 0, 0, 0},
#line 361 "rgblookup.gperf"
        {"seagreen1", 0x54, 0xff, 0x9f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 357 "rgblookup.gperf"
        {"darkseagreen1", 0xc1, 0xff, 0xc1},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 450 "rgblookup.gperf"
        {"brown2", 0xee, 0x3b, 0x3b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 440 "rgblookup.gperf"
        {"tan4", 0x8b, 0x5a, 0x2b},
        {"", 0, 0, 0},
#line 449 "rgblookup.gperf"
        {"brown1", 0xff, 0x40, 0x40},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 439 "rgblookup.gperf"
        {"tan3", 0xcd, 0x85, 0x3f},
#line 141 "rgblookup.gperf"
        {"green", 0x00, 0xff, 0x00},
#line 177 "rgblookup.gperf"
        {"sienna", 0xa0, 0x52, 0x2d},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 124 "rgblookup.gperf"
        {"darkgreen", 0x00, 0x64, 0x00},
        {"", 0, 0, 0},
#line 138 "rgblookup.gperf"
        {"springgreen", 0x00, 0xff, 0x7f},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 91 "rgblookup.gperf"
        {"blue", 0x00, 0x00, 0xff},
#line 296 "rgblookup.gperf"
        {"blue4", 0x00, 0x00, 0x8b},
#line 26 "rgblookup.gperf"
        {"bisque", 0xff, 0xe4, 0xc4},
#line 248 "rgblookup.gperf"
        {"bisque4", 0x8b, 0x7d, 0x6b},
        {"", 0, 0, 0},
#line 438 "rgblookup.gperf"
        {"tan2", 0xee, 0x9a, 0x49},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 437 "rgblookup.gperf"
        {"tan1", 0xff, 0xa5, 0x4f},
#line 295 "rgblookup.gperf"
        {"blue3", 0x00, 0x00, 0xcd},
        {"", 0, 0, 0},
#line 247 "rgblookup.gperf"
        {"bisque3", 0xcd, 0xb7, 0x9e},
        {"", 0, 0, 0},
#line 66 "rgblookup.gperf"
        {"gray", 0xbe, 0xbe, 0xbe},
#line 195 "rgblookup.gperf"
        {"darkorange", 0xff, 0x8c, 0x00},
#line 468 "rgblookup.gperf"
        {"darkorange4", 0x8b, 0x45, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 467 "rgblookup.gperf"
        {"darkorange3", 0xcd, 0x66, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 466 "rgblookup.gperf"
        {"darkorange2", 0xee, 0x76, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 294 "rgblookup.gperf"
        {"blue2", 0x00, 0x00, 0xee},
#line 465 "rgblookup.gperf"
        {"darkorange1", 0xff, 0x7f, 0x00},
#line 246 "rgblookup.gperf"
        {"bisque2", 0xee, 0xd5, 0xb7},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 152 "rgblookup.gperf"
        {"forestgreen", 0x22, 0x8b, 0x22},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 293 "rgblookup.gperf"
        {"blue1", 0x00, 0x00, 0xff},
        {"", 0, 0, 0},
#line 245 "rgblookup.gperf"
        {"bisque1", 0xff, 0xe4, 0xc4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 130 "rgblookup.gperf"
        {"seagreen", 0x2e, 0x8b, 0x57},
#line 129 "rgblookup.gperf"
        {"sea green", 0x2e, 0x8b, 0x57},
#line 40 "rgblookup.gperf"
        {"azure", 0xf0, 0xff, 0xff},
#line 284 "rgblookup.gperf"
        {"azure4", 0x83, 0x8b, 0x8b},
#line 128 "rgblookup.gperf"
        {"darkseagreen", 0x8f, 0xbc, 0x8f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 283 "rgblookup.gperf"
        {"azure3", 0xc1, 0xcd, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 170 "rgblookup.gperf"
        {"darkgoldenrod", 0xb8, 0x86, 0x0b},
#line 416 "rgblookup.gperf"
        {"darkgoldenrod4", 0x8b, 0x65, 0x08},
#line 187 "rgblookup.gperf"
        {"brown", 0xa5, 0x2a, 0x2a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 320 "rgblookup.gperf"
        {"slategray4", 0x6c, 0x7b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 415 "rgblookup.gperf"
        {"darkgoldenrod3", 0xcd, 0x95, 0x0c},
#line 319 "rgblookup.gperf"
        {"slategray3", 0x9f, 0xb6, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 282 "rgblookup.gperf"
        {"azure2", 0xe0, 0xee, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 318 "rgblookup.gperf"
        {"slategray2", 0xb9, 0xd3, 0xee},
        {"", 0, 0, 0},
#line 508 "rgblookup.gperf"
        {"maroon4", 0x8b, 0x1c, 0x62},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 317 "rgblookup.gperf"
        {"slategray1", 0xc6, 0xe2, 0xff},
#line 281 "rgblookup.gperf"
        {"azure1", 0xf0, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 507 "rgblookup.gperf"
        {"maroon3", 0xcd, 0x29, 0x90},
        {"", 0, 0, 0},
#line 414 "rgblookup.gperf"
        {"darkgoldenrod2", 0xee, 0xad, 0x0e},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 184 "rgblookup.gperf"
        {"tan", 0xd2, 0xb4, 0x8c},
#line 413 "rgblookup.gperf"
        {"darkgoldenrod1", 0xff, 0xb9, 0x0f},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 456 "rgblookup.gperf"
        {"salmon4", 0x8b, 0x4c, 0x39},
        {"", 0, 0, 0},
#line 168 "rgblookup.gperf"
        {"goldenrod", 0xda, 0xa5, 0x20},
#line 412 "rgblookup.gperf"
        {"goldenrod4", 0x8b, 0x69, 0x14},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 411 "rgblookup.gperf"
        {"goldenrod3", 0xcd, 0x9b, 0x1d},
#line 176 "rgblookup.gperf"
        {"saddlebrown", 0x8b, 0x45, 0x13},
#line 455 "rgblookup.gperf"
        {"salmon3", 0xcd, 0x70, 0x54},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 506 "rgblookup.gperf"
        {"maroon2", 0xee, 0x30, 0xa7},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 410 "rgblookup.gperf"
        {"goldenrod2", 0xee, 0xb4, 0x22},
        {"", 0, 0, 0},
#line 505 "rgblookup.gperf"
        {"maroon1", 0xff, 0x34, 0xb3},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 409 "rgblookup.gperf"
        {"goldenrod1", 0xff, 0xc1, 0x25},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 756 "rgblookup.gperf"
        {"darkmagenta", 0x8b, 0x00, 0x8b},
#line 454 "rgblookup.gperf"
        {"salmon2", 0xee, 0x82, 0x62},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 757 "rgblookup.gperf"
        {"dark red", 0x8b, 0x00, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 453 "rgblookup.gperf"
        {"salmon1", 0xff, 0x8c, 0x69},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 748 "rgblookup.gperf"
        {"darkgrey", 0xa9, 0xa9, 0xa9},
        {"", 0, 0, 0},
#line 760 "rgblookup.gperf"
        {"lightgreen", 0x90, 0xee, 0x90},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 752 "rgblookup.gperf"
        {"darkblue", 0x00, 0x00, 0x8b},
        {"", 0, 0, 0},
#line 93 "rgblookup.gperf"
        {"dodgerblue", 0x1e, 0x90, 0xff},
#line 300 "rgblookup.gperf"
        {"dodgerblue4", 0x10, 0x4e, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 299 "rgblookup.gperf"
        {"dodgerblue3", 0x18, 0x74, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 47 "rgblookup.gperf"
        {"mistyrose", 0xff, 0xe4, 0xe1},
#line 280 "rgblookup.gperf"
        {"mistyrose4", 0x8b, 0x7d, 0x7b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 279 "rgblookup.gperf"
        {"mistyrose3", 0xcd, 0xb7, 0xb5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 298 "rgblookup.gperf"
        {"dodgerblue2", 0x1c, 0x86, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 297 "rgblookup.gperf"
        {"dodgerblue1", 0x1e, 0x90, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 278 "rgblookup.gperf"
        {"mistyrose2", 0xee, 0xd5, 0xd2},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 277 "rgblookup.gperf"
        {"mistyrose1", 0xff, 0xe4, 0xe1},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 516 "rgblookup.gperf"
        {"magenta4", 0x8b, 0x00, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 515 "rgblookup.gperf"
        {"magenta3", 0xcd, 0x00, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 476 "rgblookup.gperf"
        {"tomato4", 0x8b, 0x36, 0x26},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 212 "rgblookup.gperf"
        {"maroon", 0xb0, 0x30, 0x60},
#line 475 "rgblookup.gperf"
        {"tomato3", 0xcd, 0x4f, 0x39},
#line 750 "rgblookup.gperf"
        {"darkgray", 0xa9, 0xa9, 0xa9},
#line 61 "rgblookup.gperf"
        {"slategrey", 0x70, 0x80, 0x90},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 514 "rgblookup.gperf"
        {"magenta2", 0xee, 0x00, 0xee},
#line 82 "rgblookup.gperf"
        {"slateblue", 0x6a, 0x5a, 0xcd},
#line 288 "rgblookup.gperf"
        {"slateblue4", 0x47, 0x3c, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 287 "rgblookup.gperf"
        {"slateblue3", 0x69, 0x59, 0xcd},
#line 190 "rgblookup.gperf"
        {"salmon", 0xfa, 0x80, 0x72},
        {"", 0, 0, 0},
#line 513 "rgblookup.gperf"
        {"magenta1", 0xff, 0x00, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 474 "rgblookup.gperf"
        {"tomato2", 0xee, 0x5c, 0x42},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 286 "rgblookup.gperf"
        {"slateblue2", 0x7a, 0x67, 0xee},
        {"", 0, 0, 0},
#line 473 "rgblookup.gperf"
        {"tomato1", 0xff, 0x63, 0x47},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 285 "rgblookup.gperf"
        {"slateblue1", 0x83, 0x6f, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 217 "rgblookup.gperf"
        {"magenta", 0xff, 0x00, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 180 "rgblookup.gperf"
        {"beige", 0xf5, 0xf5, 0xdc},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 123 "rgblookup.gperf"
        {"dark green", 0x00, 0x64, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 59 "rgblookup.gperf"
        {"slategray", 0x70, 0x80, 0x90},
#line 19 "rgblookup.gperf"
        {"linen", 0xfa, 0xf0, 0xe6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 199 "rgblookup.gperf"
        {"tomato", 0xff, 0x63, 0x47},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 200 "rgblookup.gperf"
        {"orange red", 0xff, 0x45, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 57 "rgblookup.gperf"
        {"dimgrey", 0x69, 0x69, 0x69},
#line 56 "rgblookup.gperf"
        {"dim grey", 0x69, 0x69, 0x69},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 148 "rgblookup.gperf"
        {"limegreen", 0x32, 0xcd, 0x32},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 92 "rgblookup.gperf"
        {"dodger blue", 0x1e, 0x90, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 189 "rgblookup.gperf"
        {"darksalmon", 0xe9, 0x96, 0x7a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 101 "rgblookup.gperf"
        {"steelblue", 0x46, 0x82, 0xb4},
#line 304 "rgblookup.gperf"
        {"steelblue4", 0x36, 0x64, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 303 "rgblookup.gperf"
        {"steelblue3", 0x4f, 0x94, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 134 "rgblookup.gperf"
        {"lightseagreen", 0x20, 0xb2, 0xaa},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 80 "rgblookup.gperf"
        {"darkslateblue", 0x48, 0x3d, 0x8b},
        {"", 0, 0, 0},
#line 302 "rgblookup.gperf"
        {"steelblue2", 0x5c, 0xac, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 301 "rgblookup.gperf"
        {"steelblue1", 0x63, 0xb8, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 167 "rgblookup.gperf"
        {"lightgoldenrod", 0xee, 0xdd, 0x82},
#line 396 "rgblookup.gperf"
        {"lightgoldenrod4", 0x8b, 0x81, 0x4c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 55 "rgblookup.gperf"
        {"dimgray", 0x69, 0x69, 0x69},
#line 54 "rgblookup.gperf"
        {"dim gray", 0x69, 0x69, 0x69},
#line 352 "rgblookup.gperf"
        {"darkslategray4", 0x52, 0x8b, 0x8b},
#line 395 "rgblookup.gperf"
        {"lightgoldenrod3", 0xcd, 0xbe, 0x70},
        {"", 0, 0, 0},
#line 97 "rgblookup.gperf"
        {"skyblue", 0x87, 0xce, 0xeb},
#line 312 "rgblookup.gperf"
        {"skyblue4", 0x4a, 0x70, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 96 "rgblookup.gperf"
        {"sky blue", 0x87, 0xce, 0xeb},
#line 351 "rgblookup.gperf"
        {"darkslategray3", 0x79, 0xcd, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 311 "rgblookup.gperf"
        {"skyblue3", 0x6c, 0xa6, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 394 "rgblookup.gperf"
        {"lightgoldenrod2", 0xee, 0xdc, 0x82},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 734 "rgblookup.gperf"
        {"grey94", 0xf0, 0xf0, 0xf0},
#line 674 "rgblookup.gperf"
        {"grey64", 0xa3, 0xa3, 0xa3},
        {"", 0, 0, 0},
#line 350 "rgblookup.gperf"
        {"darkslategray2", 0x8d, 0xee, 0xee},
#line 393 "rgblookup.gperf"
        {"lightgoldenrod1", 0xff, 0xec, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 310 "rgblookup.gperf"
        {"skyblue2", 0x7e, 0xc0, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 732 "rgblookup.gperf"
        {"grey93", 0xed, 0xed, 0xed},
#line 672 "rgblookup.gperf"
        {"grey63", 0xa1, 0xa1, 0xa1},
        {"", 0, 0, 0},
#line 349 "rgblookup.gperf"
        {"darkslategray1", 0x97, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 309 "rgblookup.gperf"
        {"skyblue1", 0x87, 0xce, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 460 "rgblookup.gperf"
        {"lightsalmon4", 0x8b, 0x57, 0x42},
#line 384 "rgblookup.gperf"
        {"olivedrab4", 0x69, 0x8b, 0x22},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 194 "rgblookup.gperf"
        {"dark orange", 0xff, 0x8c, 0x00},
#line 154 "rgblookup.gperf"
        {"olivedrab", 0x6b, 0x8e, 0x23},
#line 383 "rgblookup.gperf"
        {"olivedrab3", 0x9a, 0xcd, 0x32},
        {"", 0, 0, 0},
#line 60 "rgblookup.gperf"
        {"slate grey", 0x70, 0x80, 0x90},
        {"", 0, 0, 0},
#line 459 "rgblookup.gperf"
        {"lightsalmon3", 0xcd, 0x81, 0x62},
#line 740 "rgblookup.gperf"
        {"grey97", 0xf7, 0xf7, 0xf7},
#line 680 "rgblookup.gperf"
        {"grey67", 0xab, 0xab, 0xab},
#line 49 "rgblookup.gperf"
        {"black", 0x00, 0x00, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 730 "rgblookup.gperf"
        {"grey92", 0xeb, 0xeb, 0xeb},
#line 670 "rgblookup.gperf"
        {"grey62", 0x9e, 0x9e, 0x9e},
#line 382 "rgblookup.gperf"
        {"olivedrab2", 0xb3, 0xee, 0x3a},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 95 "rgblookup.gperf"
        {"deepskyblue", 0x00, 0xbf, 0xff},
#line 308 "rgblookup.gperf"
        {"deepskyblue4", 0x00, 0x68, 0x8b},
#line 381 "rgblookup.gperf"
        {"olivedrab1", 0xc0, 0xff, 0x3e},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 728 "rgblookup.gperf"
        {"grey91", 0xe8, 0xe8, 0xe8},
#line 668 "rgblookup.gperf"
        {"grey61", 0x9c, 0x9c, 0x9c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 307 "rgblookup.gperf"
        {"deepskyblue3", 0x00, 0x9a, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 458 "rgblookup.gperf"
        {"lightsalmon2", 0xee, 0x95, 0x72},
        {"", 0, 0, 0},
#line 69 "rgblookup.gperf"
        {"lightgrey", 0xd3, 0xd3, 0xd3},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 457 "rgblookup.gperf"
        {"lightsalmon1", 0xff, 0xa0, 0x7a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 714 "rgblookup.gperf"
        {"grey84", 0xd6, 0xd6, 0xd6},
#line 174 "rgblookup.gperf"
        {"indianred", 0xcd, 0x5c, 0x5c},
#line 424 "rgblookup.gperf"
        {"indianred4", 0x8b, 0x3a, 0x3a},
#line 105 "rgblookup.gperf"
        {"lightblue", 0xad, 0xd8, 0xe6},
#line 328 "rgblookup.gperf"
        {"lightblue4", 0x68, 0x83, 0x8b},
#line 733 "rgblookup.gperf"
        {"gray94", 0xf0, 0xf0, 0xf0},
#line 673 "rgblookup.gperf"
        {"gray64", 0xa3, 0xa3, 0xa3},
#line 423 "rgblookup.gperf"
        {"indianred3", 0xcd, 0x55, 0x55},
        {"", 0, 0, 0},
#line 327 "rgblookup.gperf"
        {"lightblue3", 0x9a, 0xc0, 0xcd},
#line 712 "rgblookup.gperf"
        {"grey83", 0xd4, 0xd4, 0xd4},
#line 306 "rgblookup.gperf"
        {"deepskyblue2", 0x00, 0xb2, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 9 "rgblookup.gperf"
        {"snow", 0xff, 0xfa, 0xfa},
#line 731 "rgblookup.gperf"
        {"gray93", 0xed, 0xed, 0xed},
#line 671 "rgblookup.gperf"
        {"gray63", 0xa1, 0xa1, 0xa1},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 305 "rgblookup.gperf"
        {"deepskyblue1", 0x00, 0xbf, 0xff},
#line 422 "rgblookup.gperf"
        {"indianred2", 0xee, 0x63, 0x63},
        {"", 0, 0, 0},
#line 326 "rgblookup.gperf"
        {"lightblue2", 0xb2, 0xdf, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 421 "rgblookup.gperf"
        {"indianred1", 0xff, 0x6a, 0x6a},
#line 169 "rgblookup.gperf"
        {"dark goldenrod", 0xb8, 0x86, 0x0b},
#line 325 "rgblookup.gperf"
        {"lightblue1", 0xbf, 0xef, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 720 "rgblookup.gperf"
        {"grey87", 0xde, 0xde, 0xde},
        {"", 0, 0, 0},
#line 58 "rgblookup.gperf"
        {"slate gray", 0x70, 0x80, 0x90},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 739 "rgblookup.gperf"
        {"gray97", 0xf7, 0xf7, 0xf7},
#line 679 "rgblookup.gperf"
        {"gray67", 0xab, 0xab, 0xab},
        {"", 0, 0, 0},
#line 710 "rgblookup.gperf"
        {"grey82", 0xd1, 0xd1, 0xd1},
#line 755 "rgblookup.gperf"
        {"dark magenta", 0x8b, 0x00, 0x8b},
#line 111 "rgblookup.gperf"
        {"darkturquoise", 0x00, 0xce, 0xd1},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 729 "rgblookup.gperf"
        {"gray92", 0xeb, 0xeb, 0xeb},
#line 669 "rgblookup.gperf"
        {"gray62", 0x9e, 0x9e, 0x9e},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 708 "rgblookup.gperf"
        {"grey81", 0xcf, 0xcf, 0xcf},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 727 "rgblookup.gperf"
        {"gray91", 0xe8, 0xe8, 0xe8},
#line 667 "rgblookup.gperf"
        {"gray61", 0x9c, 0x9c, 0x9c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 14 "rgblookup.gperf"
        {"gainsboro", 0xdc, 0xdc, 0xdc},
        {"", 0, 0, 0},
#line 71 "rgblookup.gperf"
        {"lightgray", 0xd3, 0xd3, 0xd3},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 436 "rgblookup.gperf"
        {"wheat4", 0x8b, 0x7e, 0x66},
#line 53 "rgblookup.gperf"
        {"darkslategrey", 0x2f, 0x4f, 0x4f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 713 "rgblookup.gperf"
        {"gray84", 0xd6, 0xd6, 0xd6},
#line 435 "rgblookup.gperf"
        {"wheat3", 0xcd, 0xba, 0x96},
        {"", 0, 0, 0},
#line 216 "rgblookup.gperf"
        {"violetred", 0xd0, 0x20, 0x90},
#line 512 "rgblookup.gperf"
        {"violetred4", 0x8b, 0x22, 0x52},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 511 "rgblookup.gperf"
        {"violetred3", 0xcd, 0x32, 0x78},
#line 711 "rgblookup.gperf"
        {"gray83", 0xd4, 0xd4, 0xd4},
#line 137 "rgblookup.gperf"
        {"spring green", 0x00, 0xff, 0x7f},
#line 654 "rgblookup.gperf"
        {"grey54", 0x8a, 0x8a, 0x8a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 652 "rgblookup.gperf"
        {"grey53", 0x87, 0x87, 0x87},
        {"", 0, 0, 0},
#line 510 "rgblookup.gperf"
        {"violetred2", 0xee, 0x3a, 0x8c},
#line 192 "rgblookup.gperf"
        {"lightsalmon", 0xff, 0xa0, 0x7a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 509 "rgblookup.gperf"
        {"violetred1", 0xff, 0x3e, 0x96},
        {"", 0, 0, 0},
#line 434 "rgblookup.gperf"
        {"wheat2", 0xee, 0xd8, 0xae},
#line 719 "rgblookup.gperf"
        {"gray87", 0xde, 0xde, 0xde},
#line 90 "rgblookup.gperf"
        {"royalblue", 0x41, 0x69, 0xe1},
#line 292 "rgblookup.gperf"
        {"royalblue4", 0x27, 0x40, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 291 "rgblookup.gperf"
        {"royalblue3", 0x3a, 0x5f, 0xcd},
#line 709 "rgblookup.gperf"
        {"gray82", 0xd1, 0xd1, 0xd1},
#line 433 "rgblookup.gperf"
        {"wheat1", 0xff, 0xe7, 0xba},
        {"", 0, 0, 0},
#line 268 "rgblookup.gperf"
        {"ivory4", 0x8b, 0x8b, 0x83},
#line 660 "rgblookup.gperf"
        {"grey57", 0x91, 0x91, 0x91},
        {"", 0, 0, 0},
#line 99 "rgblookup.gperf"
        {"lightskyblue", 0x87, 0xce, 0xfa},
#line 316 "rgblookup.gperf"
        {"lightskyblue4", 0x60, 0x7b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 707 "rgblookup.gperf"
        {"gray81", 0xcf, 0xcf, 0xcf},
        {"", 0, 0, 0},
#line 650 "rgblookup.gperf"
        {"grey52", 0x85, 0x85, 0x85},
#line 267 "rgblookup.gperf"
        {"ivory3", 0xcd, 0xcd, 0xc1},
#line 290 "rgblookup.gperf"
        {"royalblue2", 0x43, 0x6e, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 315 "rgblookup.gperf"
        {"lightskyblue3", 0x8d, 0xb6, 0xcd},
#line 747 "rgblookup.gperf"
        {"dark grey", 0xa9, 0xa9, 0xa9},
#line 289 "rgblookup.gperf"
        {"royalblue1", 0x48, 0x76, 0xff},
#line 759 "rgblookup.gperf"
        {"light green", 0x90, 0xee, 0x90},
#line 151 "rgblookup.gperf"
        {"forest green", 0x22, 0x8b, 0x22},
#line 648 "rgblookup.gperf"
        {"grey51", 0x82, 0x82, 0x82},
        {"", 0, 0, 0},
#line 348 "rgblookup.gperf"
        {"cyan4", 0x00, 0x8b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 175 "rgblookup.gperf"
        {"saddle brown", 0x8b, 0x45, 0x13},
#line 51 "rgblookup.gperf"
        {"darkslategray", 0x2f, 0x4f, 0x4f},
#line 751 "rgblookup.gperf"
        {"dark blue", 0x00, 0x00, 0x8b},
#line 347 "rgblookup.gperf"
        {"cyan3", 0x00, 0xcd, 0xcd},
        {"", 0, 0, 0},
#line 400 "rgblookup.gperf"
        {"lightyellow4", 0x8b, 0x8b, 0x7a},
        {"", 0, 0, 0},
#line 103 "rgblookup.gperf"
        {"lightsteelblue", 0xb0, 0xc4, 0xde},
#line 324 "rgblookup.gperf"
        {"lightsteelblue4", 0x6e, 0x7b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 266 "rgblookup.gperf"
        {"ivory2", 0xee, 0xee, 0xe0},
#line 46 "rgblookup.gperf"
        {"misty rose", 0xff, 0xe4, 0xe1},
        {"", 0, 0, 0},
#line 399 "rgblookup.gperf"
        {"lightyellow3", 0xcd, 0xcd, 0xb4},
#line 314 "rgblookup.gperf"
        {"lightskyblue2", 0xa4, 0xd3, 0xee},
        {"", 0, 0, 0},
#line 323 "rgblookup.gperf"
        {"lightsteelblue3", 0xa2, 0xb5, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 653 "rgblookup.gperf"
        {"gray54", 0x8a, 0x8a, 0x8a},
#line 265 "rgblookup.gperf"
        {"ivory1", 0xff, 0xff, 0xf0},
#line 147 "rgblookup.gperf"
        {"lime green", 0x32, 0xcd, 0x32},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 313 "rgblookup.gperf"
        {"lightskyblue1", 0xb0, 0xe2, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 651 "rgblookup.gperf"
        {"gray53", 0x87, 0x87, 0x87},
        {"", 0, 0, 0},
#line 346 "rgblookup.gperf"
        {"cyan2", 0x00, 0xee, 0xee},
#line 420 "rgblookup.gperf"
        {"rosybrown4", 0x8b, 0x69, 0x69},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 419 "rgblookup.gperf"
        {"rosybrown3", 0xcd, 0x9b, 0x9b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 345 "rgblookup.gperf"
        {"cyan1", 0x00, 0xff, 0xff},
        {"", 0, 0, 0},
#line 398 "rgblookup.gperf"
        {"lightyellow2", 0xee, 0xee, 0xd1},
        {"", 0, 0, 0},
#line 132 "rgblookup.gperf"
        {"mediumseagreen", 0x3c, 0xb3, 0x71},
#line 322 "rgblookup.gperf"
        {"lightsteelblue2", 0xbc, 0xd2, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 43 "rgblookup.gperf"
        {"lavender", 0xe6, 0xe6, 0xfa},
        {"", 0, 0, 0},
#line 659 "rgblookup.gperf"
        {"gray57", 0x91, 0x91, 0x91},
#line 418 "rgblookup.gperf"
        {"rosybrown2", 0xee, 0xb4, 0xb4},
#line 397 "rgblookup.gperf"
        {"lightyellow1", 0xff, 0xff, 0xe0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 321 "rgblookup.gperf"
        {"lightsteelblue1", 0xca, 0xe1, 0xff},
#line 417 "rgblookup.gperf"
        {"rosybrown1", 0xff, 0xc1, 0xc1},
        {"", 0, 0, 0},
#line 649 "rgblookup.gperf"
        {"gray52", 0x85, 0x85, 0x85},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 749 "rgblookup.gperf"
        {"dark gray", 0xa9, 0xa9, 0xa9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 647 "rgblookup.gperf"
        {"gray51", 0x82, 0x82, 0x82},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 181 "rgblookup.gperf"
        {"wheat", 0xf5, 0xde, 0xb3},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 392 "rgblookup.gperf"
        {"khaki4", 0x8b, 0x86, 0x4e},
#line 81 "rgblookup.gperf"
        {"slate blue", 0x6a, 0x5a, 0xcd},
#line 218 "rgblookup.gperf"
        {"violet", 0xee, 0x82, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 391 "rgblookup.gperf"
        {"khaki3", 0xcd, 0xc6, 0x73},
#line 68 "rgblookup.gperf"
        {"light grey", 0xd3, 0xd3, 0xd3},
        {"", 0, 0, 0},
#line 18 "rgblookup.gperf"
        {"oldlace", 0xfd, 0xf5, 0xe6},
        {"", 0, 0, 0},
#line 74 "rgblookup.gperf"
        {"navy", 0x00, 0x00, 0x80},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 188 "rgblookup.gperf"
        {"dark salmon", 0xe9, 0x96, 0x7a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 496 "rgblookup.gperf"
        {"pink4", 0x8b, 0x63, 0x6c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 240 "rgblookup.gperf"
        {"seashell4", 0x8b, 0x86, 0x82},
#line 495 "rgblookup.gperf"
        {"pink3", 0xcd, 0x91, 0x9e},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 390 "rgblookup.gperf"
        {"khaki2", 0xee, 0xe6, 0x85},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 239 "rgblookup.gperf"
        {"seashell3", 0xcd, 0xc5, 0xbf},
        {"", 0, 0, 0},
#line 472 "rgblookup.gperf"
        {"coral4", 0x8b, 0x3e, 0x2f},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 389 "rgblookup.gperf"
        {"khaki1", 0xff, 0xf6, 0x8f},
#line 232 "rgblookup.gperf"
        {"thistle", 0xd8, 0xbf, 0xd8},
#line 544 "rgblookup.gperf"
        {"thistle4", 0x8b, 0x7b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 471 "rgblookup.gperf"
        {"coral3", 0xcd, 0x5b, 0x45},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 543 "rgblookup.gperf"
        {"thistle3", 0xcd, 0xb5, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 494 "rgblookup.gperf"
        {"pink2", 0xee, 0xa9, 0xb8},
#line 182 "rgblookup.gperf"
        {"sandy brown", 0xf4, 0xa4, 0x60},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 115 "rgblookup.gperf"
        {"cyan", 0x00, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 238 "rgblookup.gperf"
        {"seashell2", 0xee, 0xe5, 0xde},
#line 493 "rgblookup.gperf"
        {"pink1", 0xff, 0xb5, 0xc5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 229 "rgblookup.gperf"
        {"purple", 0xa0, 0x20, 0xf0},
#line 536 "rgblookup.gperf"
        {"purple4", 0x55, 0x1a, 0x8b},
        {"", 0, 0, 0},
#line 237 "rgblookup.gperf"
        {"seashell1", 0xff, 0xf5, 0xee},
        {"", 0, 0, 0},
#line 470 "rgblookup.gperf"
        {"coral2", 0xee, 0x6a, 0x50},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 70 "rgblookup.gperf"
        {"light gray", 0xd3, 0xd3, 0xd3},
#line 542 "rgblookup.gperf"
        {"thistle2", 0xee, 0xd2, 0xee},
#line 535 "rgblookup.gperf"
        {"purple3", 0x7d, 0x26, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 469 "rgblookup.gperf"
        {"coral1", 0xff, 0x72, 0x56},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 541 "rgblookup.gperf"
        {"thistle1", 0xff, 0xe1, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 88 "rgblookup.gperf"
        {"mediumblue", 0x00, 0x00, 0xcd},
        {"", 0, 0, 0},
#line 114 "rgblookup.gperf"
        {"turquoise", 0x40, 0xe0, 0xd0},
#line 344 "rgblookup.gperf"
        {"turquoise4", 0x00, 0x86, 0x8b},
        {"", 0, 0, 0},
#line 172 "rgblookup.gperf"
        {"rosybrown", 0xbc, 0x8f, 0x8f},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 343 "rgblookup.gperf"
        {"turquoise3", 0x00, 0xc5, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 534 "rgblookup.gperf"
        {"purple2", 0x91, 0x2c, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 342 "rgblookup.gperf"
        {"turquoise2", 0x00, 0xe5, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 533 "rgblookup.gperf"
        {"purple1", 0x9b, 0x30, 0xff},
#line 341 "rgblookup.gperf"
        {"turquoise1", 0x00, 0xf5, 0xff},
        {"", 0, 0, 0},
#line 100 "rgblookup.gperf"
        {"steel blue", 0x46, 0x82, 0xb4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 133 "rgblookup.gperf"
        {"light sea green", 0x20, 0xb2, 0xaa},
        {"", 0, 0, 0},
#line 42 "rgblookup.gperf"
        {"aliceblue", 0xf0, 0xf8, 0xff},
#line 33 "rgblookup.gperf"
        {"ivory", 0xff, 0xff, 0xf0},
        {"", 0, 0, 0},
#line 179 "rgblookup.gperf"
        {"burlywood", 0xde, 0xb8, 0x87},
#line 432 "rgblookup.gperf"
        {"burlywood4", 0x8b, 0x73, 0x55},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 431 "rgblookup.gperf"
        {"burlywood3", 0xcd, 0xaa, 0x7d},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 430 "rgblookup.gperf"
        {"burlywood2", 0xee, 0xc5, 0x91},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 429 "rgblookup.gperf"
        {"burlywood1", 0xff, 0xd3, 0x9b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 178 "rgblookup.gperf"
        {"peru", 0xcd, 0x85, 0x3f},
#line 524 "rgblookup.gperf"
        {"plum4", 0x8b, 0x66, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 523 "rgblookup.gperf"
        {"plum3", 0xcd, 0x96, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 65 "rgblookup.gperf"
        {"lightslategrey", 0x77, 0x88, 0x99},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 86 "rgblookup.gperf"
        {"lightslateblue", 0x84, 0x70, 0xff},
#line 140 "rgblookup.gperf"
        {"lawngreen", 0x7c, 0xfc, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 17 "rgblookup.gperf"
        {"old lace", 0xfd, 0xf5, 0xe6},
        {"", 0, 0, 0},
#line 522 "rgblookup.gperf"
        {"plum2", 0xee, 0xae, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 153 "rgblookup.gperf"
        {"olive drab", 0x6b, 0x8e, 0x23},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 521 "rgblookup.gperf"
        {"plum1", 0xff, 0xbb, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 368 "rgblookup.gperf"
        {"palegreen4", 0x54, 0x8b, 0x54},
#line 131 "rgblookup.gperf"
        {"medium sea green", 0x3c, 0xb3, 0x71},
        {"", 0, 0, 0},
#line 36 "rgblookup.gperf"
        {"seashell", 0xff, 0xf5, 0xee},
        {"", 0, 0, 0},
#line 367 "rgblookup.gperf"
        {"palegreen3", 0x7c, 0xcd, 0x7c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 196 "rgblookup.gperf"
        {"coral", 0xff, 0x7f, 0x50},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 404 "rgblookup.gperf"
        {"yellow4", 0x8b, 0x8b, 0x00},
        {"", 0, 0, 0},
#line 366 "rgblookup.gperf"
        {"palegreen2", 0x90, 0xee, 0x90},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 365 "rgblookup.gperf"
        {"palegreen1", 0x9a, 0xff, 0x9a},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 403 "rgblookup.gperf"
        {"yellow3", 0xcd, 0xcd, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 173 "rgblookup.gperf"
        {"indian red", 0xcd, 0x5c, 0x5c},
#line 63 "rgblookup.gperf"
        {"lightslategray", 0x77, 0x88, 0x99},
#line 104 "rgblookup.gperf"
        {"light blue", 0xad, 0xd8, 0xe6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 76 "rgblookup.gperf"
        {"navyblue", 0x00, 0x00, 0x80},
#line 127 "rgblookup.gperf"
        {"dark sea green", 0x8f, 0xbc, 0x8f},
        {"", 0, 0, 0},
#line 87 "rgblookup.gperf"
        {"medium blue", 0x00, 0x00, 0xcd},
        {"", 0, 0, 0},
#line 402 "rgblookup.gperf"
        {"yellow2", 0xee, 0xee, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 401 "rgblookup.gperf"
        {"yellow1", 0xff, 0xff, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 166 "rgblookup.gperf"
        {"light goldenrod", 0xee, 0xdd, 0x82},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 48 "rgblookup.gperf"
        {"white", 0xff, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 52 "rgblookup.gperf"
        {"dark slate grey", 0x2f, 0x4f, 0x4f},
        {"", 0, 0, 0},
#line 191 "rgblookup.gperf"
        {"light salmon", 0xff, 0xa0, 0x7a},
#line 122 "rgblookup.gperf"
        {"aquamarine", 0x7f, 0xff, 0xd4},
#line 356 "rgblookup.gperf"
        {"aquamarine4", 0x45, 0x8b, 0x74},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 355 "rgblookup.gperf"
        {"aquamarine3", 0x66, 0xcd, 0xaa},
#line 215 "rgblookup.gperf"
        {"violet red", 0xd0, 0x20, 0x90},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 79 "rgblookup.gperf"
        {"dark slate blue", 0x48, 0x3d, 0x8b},
#line 183 "rgblookup.gperf"
        {"sandybrown", 0xf4, 0xa4, 0x60},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 219 "rgblookup.gperf"
        {"plum", 0xdd, 0xa0, 0xdd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 354 "rgblookup.gperf"
        {"aquamarine2", 0x76, 0xee, 0xc6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 353 "rgblookup.gperf"
        {"aquamarine1", 0x7f, 0xff, 0xd4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 142 "rgblookup.gperf"
        {"chartreuse", 0x7f, 0xff, 0x00},
#line 380 "rgblookup.gperf"
        {"chartreuse4", 0x45, 0x8b, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 89 "rgblookup.gperf"
        {"royal blue", 0x41, 0x69, 0xe1},
#line 379 "rgblookup.gperf"
        {"chartreuse3", 0x66, 0xcd, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 136 "rgblookup.gperf"
        {"palegreen", 0x98, 0xfb, 0x98},
#line 84 "rgblookup.gperf"
        {"mediumslateblue", 0x7b, 0x68, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 378 "rgblookup.gperf"
        {"chartreuse2", 0x76, 0xee, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 207 "rgblookup.gperf"
        {"pink", 0xff, 0xc0, 0xcb},
        {"", 0, 0, 0},
#line 377 "rgblookup.gperf"
        {"chartreuse1", 0x7f, 0xff, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 150 "rgblookup.gperf"
        {"yellowgreen", 0x9a, 0xcd, 0x32},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 50 "rgblookup.gperf"
        {"dark slate gray", 0x2f, 0x4f, 0x4f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 171 "rgblookup.gperf"
        {"rosy brown", 0xbc, 0x8f, 0x8f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 185 "rgblookup.gperf"
        {"chocolate", 0xd2, 0x69, 0x1e},
#line 444 "rgblookup.gperf"
        {"chocolate4", 0x8b, 0x45, 0x13},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 443 "rgblookup.gperf"
        {"chocolate3", 0xcd, 0x66, 0x1d},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 754 "rgblookup.gperf"
        {"darkcyan", 0x00, 0x8b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 159 "rgblookup.gperf"
        {"palegoldenrod", 0xee, 0xe8, 0xaa},
        {"", 0, 0, 0},
#line 442 "rgblookup.gperf"
        {"chocolate2", 0xee, 0x76, 0x21},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 441 "rgblookup.gperf"
        {"chocolate1", 0xff, 0x7f, 0x24},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 564 "rgblookup.gperf"
        {"grey9", 0x17, 0x17, 0x17},
#line 644 "rgblookup.gperf"
        {"grey49", 0x7d, 0x7d, 0x7d},
#line 558 "rgblookup.gperf"
        {"grey6", 0x0f, 0x0f, 0x0f},
#line 638 "rgblookup.gperf"
        {"grey46", 0x75, 0x75, 0x75},
#line 119 "rgblookup.gperf"
        {"cadetblue", 0x5f, 0x9e, 0xa0},
#line 340 "rgblookup.gperf"
        {"cadetblue4", 0x53, 0x86, 0x8b},
#line 624 "rgblookup.gperf"
        {"grey39", 0x63, 0x63, 0x63},
        {"", 0, 0, 0},
#line 618 "rgblookup.gperf"
        {"grey36", 0x5c, 0x5c, 0x5c},
        {"", 0, 0, 0},
#line 339 "rgblookup.gperf"
        {"cadetblue3", 0x7a, 0xc5, 0xcd},
        {"", 0, 0, 0},
#line 146 "rgblookup.gperf"
        {"greenyellow", 0xad, 0xff, 0x2f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 704 "rgblookup.gperf"
        {"grey79", 0xc9, 0xc9, 0xc9},
        {"", 0, 0, 0},
#line 698 "rgblookup.gperf"
        {"grey76", 0xc2, 0xc2, 0xc2},
#line 73 "rgblookup.gperf"
        {"midnightblue", 0x19, 0x19, 0x70},
#line 604 "rgblookup.gperf"
        {"grey29", 0x4a, 0x4a, 0x4a},
        {"", 0, 0, 0},
#line 598 "rgblookup.gperf"
        {"grey26", 0x42, 0x42, 0x42},
        {"", 0, 0, 0},
#line 338 "rgblookup.gperf"
        {"cadetblue2", 0x8e, 0xe5, 0xee},
#line 584 "rgblookup.gperf"
        {"grey19", 0x30, 0x30, 0x30},
        {"", 0, 0, 0},
#line 578 "rgblookup.gperf"
        {"grey16", 0x29, 0x29, 0x29},
        {"", 0, 0, 0},
#line 337 "rgblookup.gperf"
        {"cadetblue1", 0x98, 0xf5, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 139 "rgblookup.gperf"
        {"lawn green", 0x7c, 0xfc, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 198 "rgblookup.gperf"
        {"lightcoral", 0xf0, 0x80, 0x80},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 220 "rgblookup.gperf"
        {"orchid", 0xda, 0x70, 0xd6},
#line 520 "rgblookup.gperf"
        {"orchid4", 0x8b, 0x47, 0x89},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 563 "rgblookup.gperf"
        {"gray9", 0x17, 0x17, 0x17},
#line 643 "rgblookup.gperf"
        {"gray49", 0x7d, 0x7d, 0x7d},
#line 557 "rgblookup.gperf"
        {"gray6", 0x0f, 0x0f, 0x0f},
#line 637 "rgblookup.gperf"
        {"gray46", 0x75, 0x75, 0x75},
        {"", 0, 0, 0},
#line 519 "rgblookup.gperf"
        {"orchid3", 0xcd, 0x69, 0xc9},
#line 623 "rgblookup.gperf"
        {"gray39", 0x63, 0x63, 0x63},
        {"", 0, 0, 0},
#line 617 "rgblookup.gperf"
        {"gray36", 0x5c, 0x5c, 0x5c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 703 "rgblookup.gperf"
        {"gray79", 0xc9, 0xc9, 0xc9},
        {"", 0, 0, 0},
#line 697 "rgblookup.gperf"
        {"gray76", 0xc2, 0xc2, 0xc2},
        {"", 0, 0, 0},
#line 603 "rgblookup.gperf"
        {"gray29", 0x4a, 0x4a, 0x4a},
        {"", 0, 0, 0},
#line 597 "rgblookup.gperf"
        {"gray26", 0x42, 0x42, 0x42},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 583 "rgblookup.gperf"
        {"gray19", 0x30, 0x30, 0x30},
        {"", 0, 0, 0},
#line 577 "rgblookup.gperf"
        {"gray16", 0x29, 0x29, 0x29},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 222 "rgblookup.gperf"
        {"mediumorchid", 0xba, 0x55, 0xd3},
#line 528 "rgblookup.gperf"
        {"mediumorchid4", 0x7a, 0x37, 0x8b},
#line 39 "rgblookup.gperf"
        {"mintcream", 0xf5, 0xff, 0xfa},
#line 518 "rgblookup.gperf"
        {"orchid2", 0xee, 0x7a, 0xe9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 276 "rgblookup.gperf"
        {"lavenderblush4", 0x8b, 0x83, 0x86},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 527 "rgblookup.gperf"
        {"mediumorchid3", 0xb4, 0x52, 0xcd},
        {"", 0, 0, 0},
#line 517 "rgblookup.gperf"
        {"orchid1", 0xff, 0x83, 0xfa},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 275 "rgblookup.gperf"
        {"lavenderblush3", 0xcd, 0xc1, 0xc5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 157 "rgblookup.gperf"
        {"khaki", 0xf0, 0xe6, 0x8c},
        {"", 0, 0, 0},
#line 41 "rgblookup.gperf"
        {"alice blue", 0xf0, 0xf8, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 110 "rgblookup.gperf"
        {"dark turquoise", 0x00, 0xce, 0xd1},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 562 "rgblookup.gperf"
        {"grey8", 0x14, 0x14, 0x14},
#line 642 "rgblookup.gperf"
        {"grey48", 0x7a, 0x7a, 0x7a},
        {"", 0, 0, 0},
#line 526 "rgblookup.gperf"
        {"mediumorchid2", 0xd1, 0x5f, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 622 "rgblookup.gperf"
        {"grey38", 0x61, 0x61, 0x61},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 274 "rgblookup.gperf"
        {"lavenderblush2", 0xee, 0xe0, 0xe5},
#line 546 "rgblookup.gperf"
        {"grey0", 0x00, 0x00, 0x00},
#line 626 "rgblookup.gperf"
        {"grey40", 0x66, 0x66, 0x66},
        {"", 0, 0, 0},
#line 525 "rgblookup.gperf"
        {"mediumorchid1", 0xe0, 0x66, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 606 "rgblookup.gperf"
        {"grey30", 0x4d, 0x4d, 0x4d},
#line 702 "rgblookup.gperf"
        {"grey78", 0xc7, 0xc7, 0xc7},
        {"", 0, 0, 0},
#line 273 "rgblookup.gperf"
        {"lavenderblush1", 0xff, 0xf0, 0xf5},
        {"", 0, 0, 0},
#line 602 "rgblookup.gperf"
        {"grey28", 0x47, 0x47, 0x47},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 582 "rgblookup.gperf"
        {"grey18", 0x2e, 0x2e, 0x2e},
#line 686 "rgblookup.gperf"
        {"grey70", 0xb3, 0xb3, 0xb3},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 332 "rgblookup.gperf"
        {"lightcyan4", 0x7a, 0x8b, 0x8b},
#line 586 "rgblookup.gperf"
        {"grey20", 0x33, 0x33, 0x33},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 331 "rgblookup.gperf"
        {"lightcyan3", 0xb4, 0xcd, 0xcd},
#line 566 "rgblookup.gperf"
        {"grey10", 0x1a, 0x1a, 0x1a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 330 "rgblookup.gperf"
        {"lightcyan2", 0xd1, 0xee, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 329 "rgblookup.gperf"
        {"lightcyan1", 0xe0, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 226 "rgblookup.gperf"
        {"darkviolet", 0x94, 0x00, 0xd3},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 144 "rgblookup.gperf"
        {"mediumspringgreen", 0x00, 0xfa, 0x9a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 161 "rgblookup.gperf"
        {"lightgoldenrodyellow", 0xfa, 0xfa, 0xd2},
        {"", 0, 0, 0},
#line 388 "rgblookup.gperf"
        {"darkolivegreen4", 0x6e, 0x8b, 0x3d},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 163 "rgblookup.gperf"
        {"lightyellow", 0xff, 0xff, 0xe0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 387 "rgblookup.gperf"
        {"darkolivegreen3", 0xa2, 0xcd, 0x5a},
        {"", 0, 0, 0},
#line 561 "rgblookup.gperf"
        {"gray8", 0x14, 0x14, 0x14},
#line 641 "rgblookup.gperf"
        {"gray48", 0x7a, 0x7a, 0x7a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 135 "rgblookup.gperf"
        {"pale green", 0x98, 0xfb, 0x98},
#line 621 "rgblookup.gperf"
        {"gray38", 0x61, 0x61, 0x61},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 545 "rgblookup.gperf"
        {"gray0", 0x00, 0x00, 0x00},
#line 625 "rgblookup.gperf"
        {"gray40", 0x66, 0x66, 0x66},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 605 "rgblookup.gperf"
        {"gray30", 0x4d, 0x4d, 0x4d},
#line 701 "rgblookup.gperf"
        {"gray78", 0xc7, 0xc7, 0xc7},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 272 "rgblookup.gperf"
        {"honeydew4", 0x83, 0x8b, 0x83},
#line 601 "rgblookup.gperf"
        {"gray28", 0x47, 0x47, 0x47},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 581 "rgblookup.gperf"
        {"gray18", 0x2e, 0x2e, 0x2e},
#line 685 "rgblookup.gperf"
        {"gray70", 0xb3, 0xb3, 0xb3},
#line 386 "rgblookup.gperf"
        {"darkolivegreen2", 0xbc, 0xee, 0x68},
        {"", 0, 0, 0},
#line 271 "rgblookup.gperf"
        {"honeydew3", 0xc1, 0xcd, 0xc1},
#line 585 "rgblookup.gperf"
        {"gray20", 0x33, 0x33, 0x33},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 565 "rgblookup.gperf"
        {"gray10", 0x1a, 0x1a, 0x1a},
        {"", 0, 0, 0},
#line 385 "rgblookup.gperf"
        {"darkolivegreen1", 0xca, 0xff, 0x70},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 113 "rgblookup.gperf"
        {"mediumturquoise", 0x48, 0xd1, 0xcc},
#line 75 "rgblookup.gperf"
        {"navy blue", 0x00, 0x00, 0x80},
#line 270 "rgblookup.gperf"
        {"honeydew2", 0xe0, 0xee, 0xe0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 269 "rgblookup.gperf"
        {"honeydew1", 0xf0, 0xff, 0xf0},
#line 64 "rgblookup.gperf"
        {"light slate grey", 0x77, 0x88, 0x99},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 221 "rgblookup.gperf"
        {"medium orchid", 0xba, 0x55, 0xd3},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 556 "rgblookup.gperf"
        {"grey5", 0x0d, 0x0d, 0x0d},
#line 636 "rgblookup.gperf"
        {"grey45", 0x73, 0x73, 0x73},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 117 "rgblookup.gperf"
        {"lightcyan", 0xe0, 0xff, 0xff},
#line 616 "rgblookup.gperf"
        {"grey35", 0x59, 0x59, 0x59},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 696 "rgblookup.gperf"
        {"grey75", 0xbf, 0xbf, 0xbf},
        {"", 0, 0, 0},
#line 94 "rgblookup.gperf"
        {"deep sky blue", 0x00, 0xbf, 0xff},
        {"", 0, 0, 0},
#line 596 "rgblookup.gperf"
        {"grey25", 0x40, 0x40, 0x40},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 576 "rgblookup.gperf"
        {"grey15", 0x26, 0x26, 0x26},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 231 "rgblookup.gperf"
        {"mediumpurple", 0x93, 0x70, 0xdb},
#line 540 "rgblookup.gperf"
        {"mediumpurple4", 0x5d, 0x47, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 492 "rgblookup.gperf"
        {"hotpink4", 0x8b, 0x3a, 0x62},
#line 126 "rgblookup.gperf"
        {"darkolivegreen", 0x55, 0x6b, 0x2f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 62 "rgblookup.gperf"
        {"light slate gray", 0x77, 0x88, 0x99},
        {"", 0, 0, 0},
#line 539 "rgblookup.gperf"
        {"mediumpurple3", 0x89, 0x68, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 491 "rgblookup.gperf"
        {"hotpink3", 0xcd, 0x60, 0x90},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 25 "rgblookup.gperf"
        {"blanchedalmond", 0xff, 0xeb, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 538 "rgblookup.gperf"
        {"mediumpurple2", 0x9f, 0x79, 0xee},
#line 555 "rgblookup.gperf"
        {"gray5", 0x0d, 0x0d, 0x0d},
#line 635 "rgblookup.gperf"
        {"gray45", 0x73, 0x73, 0x73},
#line 490 "rgblookup.gperf"
        {"hotpink2", 0xee, 0x6a, 0xa7},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 98 "rgblookup.gperf"
        {"light sky blue", 0x87, 0xce, 0xfa},
#line 615 "rgblookup.gperf"
        {"gray35", 0x59, 0x59, 0x59},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 537 "rgblookup.gperf"
        {"mediumpurple1", 0xab, 0x82, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 489 "rgblookup.gperf"
        {"hotpink1", 0xff, 0x6e, 0xb4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 695 "rgblookup.gperf"
        {"gray75", 0xbf, 0xbf, 0xbf},
        {"", 0, 0, 0},
#line 448 "rgblookup.gperf"
        {"firebrick4", 0x8b, 0x1a, 0x1a},
        {"", 0, 0, 0},
#line 595 "rgblookup.gperf"
        {"gray25", 0x40, 0x40, 0x40},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 447 "rgblookup.gperf"
        {"firebrick3", 0xcd, 0x26, 0x26},
        {"", 0, 0, 0},
#line 575 "rgblookup.gperf"
        {"gray15", 0x26, 0x26, 0x26},
#line 102 "rgblookup.gperf"
        {"light steel blue", 0xb0, 0xc4, 0xde},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 38 "rgblookup.gperf"
        {"mint cream", 0xf5, 0xff, 0xfa},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 446 "rgblookup.gperf"
        {"firebrick2", 0xee, 0x2c, 0x2c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 445 "rgblookup.gperf"
        {"firebrick1", 0xff, 0x30, 0x30},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 753 "rgblookup.gperf"
        {"dark cyan", 0x00, 0x8b, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 158 "rgblookup.gperf"
        {"pale goldenrod", 0xee, 0xe8, 0xaa},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 121 "rgblookup.gperf"
        {"mediumaquamarine", 0x66, 0xcd, 0xaa},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 109 "rgblookup.gperf"
        {"paleturquoise", 0xaf, 0xee, 0xee},
#line 336 "rgblookup.gperf"
        {"paleturquoise4", 0x66, 0x8b, 0x8b},
        {"", 0, 0, 0},
#line 197 "rgblookup.gperf"
        {"light coral", 0xf0, 0x80, 0x80},
#line 83 "rgblookup.gperf"
        {"medium slate blue", 0x7b, 0x68, 0xee},
        {"", 0, 0, 0},
#line 13 "rgblookup.gperf"
        {"whitesmoke", 0xf5, 0xf5, 0xf5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 335 "rgblookup.gperf"
        {"paleturquoise3", 0x96, 0xcd, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 118 "rgblookup.gperf"
        {"cadet blue", 0x5f, 0x9e, 0xa0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 21 "rgblookup.gperf"
        {"antiquewhite", 0xfa, 0xeb, 0xd7},
#line 244 "rgblookup.gperf"
        {"antiquewhite4", 0x8b, 0x83, 0x78},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 228 "rgblookup.gperf"
        {"blueviolet", 0x8a, 0x2b, 0xe2},
#line 20 "rgblookup.gperf"
        {"antique white", 0xfa, 0xeb, 0xd7},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 243 "rgblookup.gperf"
        {"antiquewhite3", 0xcd, 0xc0, 0xb0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 334 "rgblookup.gperf"
        {"paleturquoise2", 0xae, 0xee, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 333 "rgblookup.gperf"
        {"paleturquoise1", 0xbb, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 164 "rgblookup.gperf"
        {"yellow", 0xff, 0xff, 0x00},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 31 "rgblookup.gperf"
        {"moccasin", 0xff, 0xe4, 0xb5},
#line 488 "rgblookup.gperf"
        {"deeppink4", 0x8b, 0x0a, 0x50},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 242 "rgblookup.gperf"
        {"antiquewhite2", 0xee, 0xdf, 0xcc},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 487 "rgblookup.gperf"
        {"deeppink3", 0xcd, 0x10, 0x76},
#line 149 "rgblookup.gperf"
        {"yellow green", 0x9a, 0xcd, 0x32},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 85 "rgblookup.gperf"
        {"light slate blue", 0x84, 0x70, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 241 "rgblookup.gperf"
        {"antiquewhite1", 0xff, 0xef, 0xdb},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 264 "rgblookup.gperf"
        {"cornsilk4", 0x8b, 0x88, 0x78},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 223 "rgblookup.gperf"
        {"dark orchid", 0x99, 0x32, 0xcc},
#line 263 "rgblookup.gperf"
        {"cornsilk3", 0xcd, 0xc8, 0xb1},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 486 "rgblookup.gperf"
        {"deeppink2", 0xee, 0x12, 0x89},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 485 "rgblookup.gperf"
        {"deeppink1", 0xff, 0x14, 0x93},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 262 "rgblookup.gperf"
        {"cornsilk2", 0xee, 0xe8, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 160 "rgblookup.gperf"
        {"light goldenrod yellow", 0xfa, 0xfa, 0xd2},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 261 "rgblookup.gperf"
        {"cornsilk1", 0xff, 0xf8, 0xdc},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 12 "rgblookup.gperf"
        {"white smoke", 0xf5, 0xf5, 0xf5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 116 "rgblookup.gperf"
        {"light cyan", 0xe0, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 214 "rgblookup.gperf"
        {"mediumvioletred", 0xc7, 0x15, 0x85},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 107 "rgblookup.gperf"
        {"powderblue", 0xb0, 0xe0, 0xe6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 120 "rgblookup.gperf"
        {"medium aquamarine", 0x66, 0xcd, 0xaa},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 225 "rgblookup.gperf"
        {"dark violet", 0x94, 0x00, 0xd3},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 125 "rgblookup.gperf"
        {"dark olive green", 0x55, 0x6b, 0x2f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 224 "rgblookup.gperf"
        {"darkorchid", 0x99, 0x32, 0xcc},
#line 532 "rgblookup.gperf"
        {"darkorchid4", 0x68, 0x22, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 531 "rgblookup.gperf"
        {"darkorchid3", 0x9a, 0x32, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 530 "rgblookup.gperf"
        {"darkorchid2", 0xb2, 0x3a, 0xee},
#line 204 "rgblookup.gperf"
        {"hotpink", 0xff, 0x69, 0xb4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 529 "rgblookup.gperf"
        {"darkorchid1", 0xbf, 0x3e, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 45 "rgblookup.gperf"
        {"lavenderblush", 0xff, 0xf0, 0xf5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 15 "rgblookup.gperf"
        {"floral white", 0xff, 0xfa, 0xf0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 186 "rgblookup.gperf"
        {"firebrick", 0xb2, 0x22, 0x22},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 744 "rgblookup.gperf"
        {"grey99", 0xfc, 0xfc, 0xfc},
#line 684 "rgblookup.gperf"
        {"grey69", 0xb0, 0xb0, 0xb0},
#line 738 "rgblookup.gperf"
        {"grey96", 0xf5, 0xf5, 0xf5},
#line 678 "rgblookup.gperf"
        {"grey66", 0xa8, 0xa8, 0xa8},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 72 "rgblookup.gperf"
        {"midnight blue", 0x19, 0x19, 0x70},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 11 "rgblookup.gperf"
        {"ghostwhite", 0xf8, 0xf8, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 106 "rgblookup.gperf"
        {"powder blue", 0xb0, 0xe0, 0xe6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 724 "rgblookup.gperf"
        {"grey89", 0xe3, 0xe3, 0xe3},
        {"", 0, 0, 0},
#line 718 "rgblookup.gperf"
        {"grey86", 0xdb, 0xdb, 0xdb},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 743 "rgblookup.gperf"
        {"gray99", 0xfc, 0xfc, 0xfc},
#line 683 "rgblookup.gperf"
        {"gray69", 0xb0, 0xb0, 0xb0},
#line 737 "rgblookup.gperf"
        {"gray96", 0xf5, 0xf5, 0xf5},
#line 677 "rgblookup.gperf"
        {"gray66", 0xa8, 0xa8, 0xa8},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 500 "rgblookup.gperf"
        {"lightpink4", 0x8b, 0x5f, 0x65},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 499 "rgblookup.gperf"
        {"lightpink3", 0xcd, 0x8c, 0x95},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 16 "rgblookup.gperf"
        {"floralwhite", 0xff, 0xfa, 0xf0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 498 "rgblookup.gperf"
        {"lightpink2", 0xee, 0xa2, 0xad},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 206 "rgblookup.gperf"
        {"deeppink", 0xff, 0x14, 0x93},
        {"", 0, 0, 0},
#line 497 "rgblookup.gperf"
        {"lightpink1", 0xff, 0xae, 0xb9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 32 "rgblookup.gperf"
        {"cornsilk", 0xff, 0xf8, 0xdc},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 742 "rgblookup.gperf"
        {"grey98", 0xfa, 0xfa, 0xfa},
#line 682 "rgblookup.gperf"
        {"grey68", 0xad, 0xad, 0xad},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 723 "rgblookup.gperf"
        {"gray89", 0xe3, 0xe3, 0xe3},
        {"", 0, 0, 0},
#line 717 "rgblookup.gperf"
        {"gray86", 0xdb, 0xdb, 0xdb},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 726 "rgblookup.gperf"
        {"grey90", 0xe5, 0xe5, 0xe5},
#line 666 "rgblookup.gperf"
        {"grey60", 0x99, 0x99, 0x99},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 664 "rgblookup.gperf"
        {"grey59", 0x96, 0x96, 0x96},
        {"", 0, 0, 0},
#line 658 "rgblookup.gperf"
        {"grey56", 0x8f, 0x8f, 0x8f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 24 "rgblookup.gperf"
        {"blanched almond", 0xff, 0xeb, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 78 "rgblookup.gperf"
        {"cornflowerblue", 0x64, 0x95, 0xed},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 77 "rgblookup.gperf"
        {"cornflower blue", 0x64, 0x95, 0xed},
        {"", 0, 0, 0},
#line 155 "rgblookup.gperf"
        {"dark khaki", 0xbd, 0xb7, 0x6b},
#line 227 "rgblookup.gperf"
        {"blue violet", 0x8a, 0x2b, 0xe2},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 722 "rgblookup.gperf"
        {"grey88", 0xe0, 0xe0, 0xe0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 741 "rgblookup.gperf"
        {"gray98", 0xfa, 0xfa, 0xfa},
#line 681 "rgblookup.gperf"
        {"gray68", 0xad, 0xad, 0xad},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 706 "rgblookup.gperf"
        {"grey80", 0xcc, 0xcc, 0xcc},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 37 "rgblookup.gperf"
        {"honeydew", 0xf0, 0xff, 0xf0},
#line 725 "rgblookup.gperf"
        {"gray90", 0xe5, 0xe5, 0xe5},
#line 665 "rgblookup.gperf"
        {"gray60", 0x99, 0x99, 0x99},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 663 "rgblookup.gperf"
        {"gray59", 0x96, 0x96, 0x96},
        {"", 0, 0, 0},
#line 657 "rgblookup.gperf"
        {"gray56", 0x8f, 0x8f, 0x8f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 746 "rgblookup.gperf"
        {"grey100", 0xff, 0xff, 0xff},
#line 230 "rgblookup.gperf"
        {"medium purple", 0x93, 0x70, 0xdb},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 112 "rgblookup.gperf"
        {"medium turquoise", 0x48, 0xd1, 0xcc},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 721 "rgblookup.gperf"
        {"gray88", 0xe0, 0xe0, 0xe0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 145 "rgblookup.gperf"
        {"green yellow", 0xad, 0xff, 0x2f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 705 "rgblookup.gperf"
        {"gray80", 0xcc, 0xcc, 0xcc},
        {"", 0, 0, 0},
#line 662 "rgblookup.gperf"
        {"grey58", 0x94, 0x94, 0x94},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 646 "rgblookup.gperf"
        {"grey50", 0x7f, 0x7f, 0x7f},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 736 "rgblookup.gperf"
        {"grey95", 0xf2, 0xf2, 0xf2},
#line 676 "rgblookup.gperf"
        {"grey65", 0xa6, 0xa6, 0xa6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 745 "rgblookup.gperf"
        {"gray100", 0xff, 0xff, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 156 "rgblookup.gperf"
        {"darkkhaki", 0xbd, 0xb7, 0x6b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 661 "rgblookup.gperf"
        {"gray58", 0x94, 0x94, 0x94},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 645 "rgblookup.gperf"
        {"gray50", 0x7f, 0x7f, 0x7f},
        {"", 0, 0, 0},
#line 716 "rgblookup.gperf"
        {"grey85", 0xd9, 0xd9, 0xd9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 735 "rgblookup.gperf"
        {"gray95", 0xf2, 0xf2, 0xf2},
#line 675 "rgblookup.gperf"
        {"gray65", 0xa6, 0xa6, 0xa6},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 10 "rgblookup.gperf"
        {"ghost white", 0xf8, 0xf8, 0xff},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 211 "rgblookup.gperf"
        {"palevioletred", 0xdb, 0x70, 0x93},
#line 504 "rgblookup.gperf"
        {"palevioletred4", 0x8b, 0x47, 0x5d},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 503 "rgblookup.gperf"
        {"palevioletred3", 0xcd, 0x68, 0x89},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 502 "rgblookup.gperf"
        {"palevioletred2", 0xee, 0x79, 0x9f},
        {"", 0, 0, 0}, {"", 0, 0, 0},
#line 715 "rgblookup.gperf"
        {"gray85", 0xd9, 0xd9, 0xd9},
        {"", 0, 0, 0},
#line 209 "rgblookup.gperf"
        {"lightpink", 0xff, 0xb6, 0xc1},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 501 "rgblookup.gperf"
        {"palevioletred1", 0xff, 0x82, 0xab},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 656 "rgblookup.gperf"
        {"grey55", 0x8c, 0x8c, 0x8c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 29 "rgblookup.gperf"
        {"navajo white", 0xff, 0xde, 0xad},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 162 "rgblookup.gperf"
        {"light yellow", 0xff, 0xff, 0xe0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 108 "rgblookup.gperf"
        {"pale turquoise", 0xaf, 0xee, 0xee},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 143 "rgblookup.gperf"
        {"medium spring green", 0x00, 0xfa, 0x9a},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 655 "rgblookup.gperf"
        {"gray55", 0x8c, 0x8c, 0x8c},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 260 "rgblookup.gperf"
        {"lemonchiffon4", 0x8b, 0x89, 0x70},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 259 "rgblookup.gperf"
        {"lemonchiffon3", 0xcd, 0xc9, 0xa5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 208 "rgblookup.gperf"
        {"light pink", 0xff, 0xb6, 0xc1},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 258 "rgblookup.gperf"
        {"lemonchiffon2", 0xee, 0xe9, 0xbf},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 257 "rgblookup.gperf"
        {"lemonchiffon1", 0xff, 0xfa, 0xcd},
#line 205 "rgblookup.gperf"
        {"deep pink", 0xff, 0x14, 0x93},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 30 "rgblookup.gperf"
        {"navajowhite", 0xff, 0xde, 0xad},
#line 256 "rgblookup.gperf"
        {"navajowhite4", 0x8b, 0x79, 0x5e},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 255 "rgblookup.gperf"
        {"navajowhite3", 0xcd, 0xb3, 0x8b},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0},
#line 252 "rgblookup.gperf"
        {"peachpuff4", 0x8b, 0x77, 0x65},
#line 254 "rgblookup.gperf"
        {"navajowhite2", 0xee, 0xcf, 0xa1},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 251 "rgblookup.gperf"
        {"peachpuff3", 0xcd, 0xaf, 0x95},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 253 "rgblookup.gperf"
        {"navajowhite1", 0xff, 0xde, 0xad},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 250 "rgblookup.gperf"
        {"peachpuff2", 0xee, 0xcb, 0xad},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 249 "rgblookup.gperf"
        {"peachpuff1", 0xff, 0xda, 0xb9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 35 "rgblookup.gperf"
        {"lemonchiffon", 0xff, 0xfa, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 28 "rgblookup.gperf"
        {"peachpuff", 0xff, 0xda, 0xb9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 44 "rgblookup.gperf"
        {"lavender blush", 0xff, 0xf0, 0xf5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 213 "rgblookup.gperf"
        {"medium violet red", 0xc7, 0x15, 0x85},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 203 "rgblookup.gperf"
        {"hot pink", 0xff, 0x69, 0xb4},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 27 "rgblookup.gperf"
        {"peach puff", 0xff, 0xda, 0xb9},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 34 "rgblookup.gperf"
        {"lemon chiffon", 0xff, 0xfa, 0xcd},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 210 "rgblookup.gperf"
        {"pale violet red", 0xdb, 0x70, 0x93},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 22 "rgblookup.gperf"
        {"papaya whip", 0xff, 0xef, 0xd5},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
        {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0}, {"", 0, 0, 0},
#line 23 "rgblookup.gperf"
        {"papayawhip", 0xff, 0xef, 0xd5}
    };

    if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)
    {
        unsigned int key = hash (str, len);

        if (key <= MAX_HASH_VALUE)
        {
            register const char *s = wordlist[key].name;

            if ((((unsigned char)*str ^ (unsigned char)*s) & ~32) == 0 && !gperf_case_strcmp (str, s))
                return &wordlist[key];
        }
    }
    return 0;
}
