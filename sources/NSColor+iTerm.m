//
//  NSColor+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "NSColor+iTerm.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSNumber+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "SolidColorView.h"

// Constants for converting RGB to luma.
static const double kRedComponentBrightness = 0.30;
static const double kGreenComponentBrightness = 0.59;
static const double kBlueComponentBrightness = 0.11;

NSString *const kEncodedColorDictionaryRedComponent = @"Red Component";
NSString *const kEncodedColorDictionaryGreenComponent = @"Green Component";
NSString *const kEncodedColorDictionaryBlueComponent = @"Blue Component";
NSString *const kEncodedColorDictionaryAlphaComponent = @"Alpha Component";
NSString *const kEncodedColorDictionaryColorSpace = @"Color Space";
NSString *const kEncodedColorDictionarySRGBColorSpace = @"sRGB";
NSString *const kEncodedColorDictionaryCalibratedColorSpace = @"Calibrated";
NSString *const kEncodedColorDictionaryP3ColorSpace = @"P3";

CGFloat PerceivedBrightness(CGFloat r, CGFloat g, CGFloat b) {
    return (kRedComponentBrightness * r +
            kGreenComponentBrightness * g +
            kBlueComponentBrightness * b);
}

CGFloat iTermPerceptualBrightnessSRGB(iTermSRGBColor srgb) {
    iTermRGBColor linearColor = iTermLinearizeSRGB(srgb);
    return 0.2126 * linearColor.r + 0.7152 * linearColor.g + 0.0722 * linearColor.b;
}

static CGFloat iTermLinearize(CGFloat n) {
    if (n > 0.04045) {
        return pow((n + 0.055) / 1.055, 2.4);
    } else {
        return n / 12.92;
    }
}

iTermRGBColor iTermLinearizeSRGB(iTermSRGBColor srgb) {
    CGFloat (^pivot)(CGFloat) = ^CGFloat(CGFloat n) {
        return iTermLinearize(n);
    };
    return (iTermRGBColor) {
        .r = pivot(srgb.r),
        .g = pivot(srgb.g),
        .b = pivot(srgb.b)
    };
}

// https://entropymine.com/imageworsener/srgbformula/
iTermSRGBColor iTermCompressRGB(iTermRGBColor rgb) {
    CGFloat (^pivot)(CGFloat) = ^CGFloat(CGFloat l) {
        if (l <= 0.003130) {
            return l * 12.92;
        }
        return 1.055 * pow(l, 1.0 / 2.4) - 0.055;
    };
    return (iTermSRGBColor) {
        .r = pivot(rgb.r),
        .g = pivot(rgb.g),
        .b = pivot(rgb.b)
    };
}

// Reference observer. D65 illuminant, 2 degrees. Divided by 100 vs the usual values for simplicity.
static iTermXYZColor iTermD65Reference(void) {
    return (iTermXYZColor) {
        .x = 0.95047,
        .y = 1.00000,
        .z = 1.08883
    };
}

static iTermXYZColor iTermCompressXYZ(iTermXYZColor compressed) {
    CGFloat (^pivot)(CGFloat) = ^CGFloat(CGFloat l) {
        if (l > 0.008856) {
            return pow(l, 1.0 / 3.0);
        }
        return (7.787 * l) + (16.0 / 116.0);
    };
    return (iTermXYZColor) {
        .x = pivot(compressed.x),
        .y = pivot(compressed.y),
        .z = pivot(compressed.z)
    };
}

static iTermXYZColor iTermLinearizeXYZ(iTermXYZColor linear) {
    CGFloat (^pivot)(CGFloat) = ^CGFloat(CGFloat l) {
        if (pow(l, 3.0) > 0.008856) {
            return pow(l, 3.0);
        }
        return (l - 16.0 / 116.0) / 7.787;
    };
    return (iTermXYZColor) {
        .x = pivot(linear.x),
        .y = pivot(linear.y),
        .z = pivot(linear.z)
    };
}

iTermLABColor iTermLABFromSRGB(iTermSRGBColor srgb) {
    const iTermRGBColor rgb = iTermLinearizeSRGB(srgb);
    iTermXYZColor xyz = iTermLinearSRGBToXYZ(rgb);
    const iTermXYZColor reference = iTermD65Reference();
    xyz.x /= reference.x;
    xyz.y /= reference.y;
    xyz.z /= reference.z;
    xyz = iTermCompressXYZ(xyz);
    return (iTermLABColor) {
        .l = (116.0 * xyz.y) - 16.0,
        .a = 500.0 * (xyz.x - xyz.y),
        .b = 200.0 * (xyz.y - xyz.z)
    };
}

iTermSRGBColor iTermSRGBFromLAB(iTermLABColor lab) {
    const CGFloat tempY = (lab.l + 16.0) / 116.0;
    iTermXYZColor xyz = {
        .x = lab.a / 500.0 + tempY,
        .y = tempY,
        .z = tempY - lab.b / 200.0
    };

    xyz = iTermLinearizeXYZ(xyz);
    const iTermXYZColor reference = iTermD65Reference();

    xyz.x = reference.x * xyz.x;
    xyz.y = reference.y * xyz.y;
    xyz.z = reference.z * xyz.z;

    iTermRGBColor rgb = {
        .r = MAX(MIN(1, xyz.x *  3.2406 + xyz.y * -1.5372 + xyz.z * -0.4986), 0),
        .g = MAX(MIN(1, xyz.x * -0.9689 + xyz.y *  1.8758 + xyz.z *  0.0415), 0),
        .b = MAX(MIN(1, xyz.x *  0.0557 + xyz.y * -0.2040 + xyz.z *  1.0570), 0)
    };
    return iTermCompressRGB(rgb);
}

CGFloat iTermLABBrightnessDistance(iTermLABColor lhs, iTermLABColor rhs) {
    const iTermSRGBColor lsrgb = iTermSRGBFromLAB(lhs);
    const iTermSRGBColor rsrgb = iTermSRGBFromLAB(rhs);
    return fabs(PerceivedBrightness(lsrgb.r, lsrgb.g, lsrgb.b) -
                PerceivedBrightness(rsrgb.r, rsrgb.g, rsrgb.b));
}

CGFloat iTermLABDistance(iTermLABColor lhs, iTermLABColor rhs) {
    // Everything I can find about detla E says it's supposed to be in [0,100]
    // but it's easy to find values larger than 100. My guess is that that's
    // just a convention and that the L*ab color space is absurdly large and
    // most of it is imperceptbile, allowing theoretically huge delta E values
    // that don't happen in real life (modulo numerical errors in conversions
    // between L*ab and SRGB).
    return sqrt(pow(lhs.l - rhs.l, 2) +
                pow(lhs.a - rhs.a, 2) +
                pow(lhs.b - rhs.b, 2)) / 100.0;
}

// CIEDE2000 difference
CGFloat iTermLABDeltaE2000(iTermLABColor lab1, iTermLABColor lab2) {
    CGFloat kL = 1.0, kC = 1.0, kH = 1.0;

    CGFloat deltaLPrime = lab2.l - lab1.l;
    CGFloat LBar = (lab1.l + lab2.l) / 2.0;
    CGFloat C1 = sqrt(lab1.a * lab1.a + lab1.b * lab1.b);
    CGFloat C2 = sqrt(lab2.a * lab2.a + lab2.b * lab2.b);
    CGFloat CBar = (C1 + C2) / 2.0;
    CGFloat CBar7 = pow(CBar, 7.0);
    CGFloat G = 0.5 * (1.0 - sqrt(CBar7 / (CBar7 + pow(25.0, 7.0))));

    CGFloat a1Prime = lab1.a * (1.0 + G);
    CGFloat a2Prime = lab2.a * (1.0 + G);
    CGFloat C1Prime = sqrt(a1Prime * a1Prime + lab1.b * lab1.b);
    CGFloat C2Prime = sqrt(a2Prime * a2Prime + lab2.b * lab2.b);
    CGFloat CBarPrime = (C1Prime + C2Prime) / 2.0;

    CGFloat h1Prime = atan2(lab1.b, a1Prime);
    if (h1Prime < 0.0) {
        h1Prime += 2.0 * M_PI;
    }
    CGFloat h2Prime = atan2(lab2.b, a2Prime);
    if (h2Prime < 0.0) {
        h2Prime += 2.0 * M_PI;
    }

    CGFloat HBarPrime = (fabs(h1Prime - h2Prime) > M_PI) ?
        (h1Prime + h2Prime + 2.0 * M_PI) / 2.0 :
        (h1Prime + h2Prime) / 2.0;

    CGFloat deltaHPrime = h2Prime - h1Prime;
    if (fabs(deltaHPrime) > M_PI) {
        deltaHPrime += (deltaHPrime > 0.0) ? -2.0 * M_PI : 2.0 * M_PI;
    }
    deltaHPrime = 2.0 * sqrt(C1Prime * C2Prime) * sin(deltaHPrime / 2.0);

    CGFloat T = 1.0 - 0.17 * cos(HBarPrime - M_PI / 6.0) + 0.24 * cos(2.0 * HBarPrime) +
        0.32 * cos(3.0 * HBarPrime + M_PI / 30.0) - 0.20 * cos(4.0 * HBarPrime - 21.0 * M_PI / 60.0);

    CGFloat SL = 1.0 + ((0.015 * pow(LBar - 50.0, 2.0)) / sqrt(20.0 + pow(LBar - 50.0, 2.0)));
    CGFloat SC = 1.0 + 0.045 * CBarPrime;
    CGFloat SH = 1.0 + 0.015 * CBarPrime * T;

    CGFloat deltaTheta = (30.0 * M_PI / 180.0) * exp(-pow((HBarPrime * 180.0 / M_PI - 275.0) / 25.0, 2.0));
    CGFloat RC = 2.0 * sqrt(CBar7 / (CBar7 + pow(25.0, 7.0)));
    CGFloat RT = -sin(2.0 * deltaTheta) * RC;

    CGFloat deltaE = (sqrt(pow(deltaLPrime / (kL * SL), 2.0) +
                           pow((C2Prime - C1Prime) / (kC * SC), 2.0) +
                           pow(deltaHPrime / (kH * SH), 2.0) +
                           RT * (C2Prime - C1Prime) * deltaHPrime / (kC * SC * kH * SH)));

    return deltaE;
}

static CGFloat iTermCompressP3(CGFloat linearValue) {
    return pow(linearValue, 1.0 / 2.2);
}

// Remove gamma correction (linearize)
static CGFloat iTermLinearizeP3(CGFloat gammaCorrectedValue) {
    return pow(gammaCorrectedValue, 2.2);
}

// Expects nonlinear p3.
iTermXYZColor iTermP3ToXYZ(iTermP3Color p3) {
    // P3 to XYZ transformation matrix
    const CGFloat P3ToXYZ[3][3] = {
        {0.4865709486482162, 0.26566769316909306, 0.1982172852343625},
        {0.2289745640697488, 0.6917385218365064, 0.079286914093745},
        {0.0000000000000000, 0.0451133818589026, 1.0439443689009760}
    };
    iTermXYZColor xyz;
    xyz.x = P3ToXYZ[0][0] * iTermLinearizeP3(p3.r) + P3ToXYZ[0][1] * iTermLinearizeP3(p3.g) + P3ToXYZ[0][2] * iTermLinearizeP3(p3.b);
    xyz.y = P3ToXYZ[1][0] * iTermLinearizeP3(p3.r) + P3ToXYZ[1][1] * iTermLinearizeP3(p3.g) + P3ToXYZ[1][2] * iTermLinearizeP3(p3.b);
    xyz.z = P3ToXYZ[2][0] * iTermLinearizeP3(p3.r) + P3ToXYZ[2][1] * iTermLinearizeP3(p3.g) + P3ToXYZ[2][2] * iTermLinearizeP3(p3.b);

    return xyz;
}

static CGFloat iTermClampToUnitInterval(CGFloat value) {
    if (value < 0) {
        return 0;
    }
    if (value > 1) {
        return 1;
    }
    return value;
}

iTermP3Color iTermXYZToLinearP3(iTermXYZColor xyz) {
    // XYZ to P3 transformation matrix (D65 illuminant)
    const CGFloat XYZToP3[3][3] = {
        {2.493496911941425, -0.9313836179191239, -0.40271078445071684},
        {-0.8294889695615747, 1.7626640603183463, 0.023624685841943577},
        {0.03584583024378447, -0.07617238926804182, 0.9568845240076872}
    };

    iTermP3Color p3;

    // Convert XYZ to P3
    p3.r = XYZToP3[0][0] * xyz.x + XYZToP3[0][1] * xyz.y + XYZToP3[0][2] * xyz.z;
    p3.g = XYZToP3[1][0] * xyz.x + XYZToP3[1][1] * xyz.y + XYZToP3[1][2] * xyz.z;
    p3.b = XYZToP3[2][0] * xyz.x + XYZToP3[2][1] * xyz.y + XYZToP3[2][2] * xyz.z;

    return p3;
}

iTermP3Color iTermXYZToP3(iTermXYZColor xyz) {
    iTermP3Color p3 = iTermXYZToLinearP3(xyz);

    p3.r = iTermCompressP3(iTermClampToUnitInterval(p3.r));
    p3.g = iTermCompressP3(iTermClampToUnitInterval(p3.g));
    p3.b = iTermCompressP3(iTermClampToUnitInterval(p3.b));

    return p3;
}

iTermRGBColor iTermXYZToLinearSRGB(iTermXYZColor xyz) {
    // XYZ to sRGB transformation matrix
    const CGFloat XYZToSRGB[3][3] = {
        { 3.2404542, -1.5371385, -0.4985314 },
        {-0.9692660,  1.8760108,  0.0415560 },
        { 0.0556434, -0.2040259,  1.0572252 },
    };

    iTermRGBColor linearRGB;
    linearRGB.r = XYZToSRGB[0][0] * xyz.x + XYZToSRGB[0][1] * xyz.y + XYZToSRGB[0][2] * xyz.z;
    linearRGB.g = XYZToSRGB[1][0] * xyz.x + XYZToSRGB[1][1] * xyz.y + XYZToSRGB[1][2] * xyz.z;
    linearRGB.b = XYZToSRGB[2][0] * xyz.x + XYZToSRGB[2][1] * xyz.y + XYZToSRGB[2][2] * xyz.z;
    return linearRGB;
}

iTermXYZColor iTermLinearSRGBToXYZ(iTermRGBColor linearRGB) {
    // sRGB to XYZ transformation matrix (D65 illuminant)
    const CGFloat SRGBToXYZ[3][3] = {
        {0.4124564, 0.3575761, 0.1804375},
        {0.2126729, 0.7151522, 0.0721750},
        {0.0193339, 0.1191920, 0.9503041}
    };

    iTermXYZColor xyz;

    // Convert linear sRGB to XYZ
    xyz.x = SRGBToXYZ[0][0] * linearRGB.r + SRGBToXYZ[0][1] * linearRGB.g + SRGBToXYZ[0][2] * linearRGB.b;
    xyz.y = SRGBToXYZ[1][0] * linearRGB.r + SRGBToXYZ[1][1] * linearRGB.g + SRGBToXYZ[1][2] * linearRGB.b;
    xyz.z = SRGBToXYZ[2][0] * linearRGB.r + SRGBToXYZ[2][1] * linearRGB.g + SRGBToXYZ[2][2] * linearRGB.b;

    return xyz;
}
//
// Note that this can return out-of-gamut values.
iTermSRGBColor iTermP3ColorToSRGBColor(iTermP3Color p3) {
    // P3 -> linear XYZ
    iTermXYZColor xyz = iTermP3ToXYZ(p3);

    // XYZ -> linear sRGB
    iTermRGBColor linearRGB = iTermXYZToLinearSRGB(xyz);

    // Linear sRGB -> gamma corrected
    iTermSRGBColor srgb = iTermCompressRGB(linearRGB);

    return srgb;
}

iTermP3Color iTermSRGBColorToP3Color(iTermSRGBColor srgb) {
    // Gamma corrected sRGB -> Linear sRGB
    iTermRGBColor linearRGB = iTermLinearizeSRGB(srgb);

    // Linear sRGB -> XYZ
    iTermXYZColor xyz = iTermLinearSRGBToXYZ(linearRGB);

    // XYZ -> P3
    iTermP3Color p3 = iTermXYZToP3(xyz);

    return p3;
}
@implementation NSColor (iTerm)

- (iTermSRGBColor)itermSRGBColor {
    NSColor *srgb = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return (iTermSRGBColor){
        srgb.redComponent,
        srgb.greenComponent,
        srgb.blueComponent
    };
}

+ (instancetype)colorWithVector:(vector_float4)vector colorSpace:(NSColorSpace *)colorSpace {
    CGFloat components[4] = { vector.x, vector.y, vector.z, vector.w };
    return [NSColor colorWithColorSpace:colorSpace components:components count:4];
}

- (double)perceptualDistanceTo:(NSColor *)other {
    return MAX(0, iTermLABDeltaE2000([self labColor], [other labColor]) / 100.0);
}

+ (NSColor *)it_blue {
    return [NSColor colorWithName:@"iTermBlueTextColor" dynamicProvider:^NSColor * _Nonnull(NSAppearance * _Nonnull appearance) {
        if (appearance.it_isDark) {
            return [NSColor colorWithSRGBRed:0.8 green:0.8 blue:1.0 alpha:1.0];
        } else {
            return [NSColor colorWithSRGBRed:0.3 green:0.3 blue:0.55 alpha:1.0];
        }
    }];
}

- (iTermLABColor)labColor {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const iTermSRGBColor srgb = (iTermSRGBColor) {
        .r = color.redComponent,
        .g = color.blueComponent,
        .b = color.greenComponent
    };
    return iTermLABFromSRGB(srgb);
}

+ (instancetype)withLABColor:(iTermLABColor)lab {
    iTermSRGBColor srgb = iTermSRGBFromLAB(lab);
    return [[NSColor colorWithSRGBRed:srgb.r green:srgb.g blue:srgb.b alpha:1] it_colorInDefaultColorSpace];
}

- (NSString *)shortDescription {
    switch (self.type) {
        case NSColorTypeComponentBased: {
            NSString *colorSpaceDescription = @"unknown";
            NSColorSpace *colorSpace = self.colorSpace;

            switch (colorSpace.colorSpaceModel) {
                case NSColorSpaceModelUnknown:
                    return @"unknown";

                case NSColorSpaceModelGray: {
                    colorSpaceDescription = @"grayscale";
                    CGFloat alpha, white;
                    [self getWhite:&white alpha:&alpha];
                    return [NSString stringWithFormat:@"%@#%02X",
                            colorSpaceDescription,
                            (int)(white * 255)];
                }

                case NSColorSpaceModelRGB: {
                    if (colorSpace == [NSColorSpace sRGBColorSpace]) {
                        colorSpaceDescription = @"srgb";
                    } else if (colorSpace == [NSColorSpace displayP3ColorSpace]) {
                        colorSpaceDescription = @"p3";
                    } else {
                        colorSpaceDescription = colorSpace.description;
                    }

                    CGFloat red, green, blue, alpha;
                    [self getRed:&red green:&green blue:&blue alpha:&alpha];
                    return [NSString stringWithFormat:@"%@#%02X%02X%02X",
                            colorSpaceDescription,
                            (int)(red * 255), (int)(green * 255), (int)(blue * 255)];
                }

                case NSColorSpaceModelCMYK: {
                    colorSpaceDescription = @"cmyk";
                    CGFloat cyan, magenta, yellow, black, alpha;
                    [self getCyan:&cyan magenta:&magenta yellow:&yellow black:&black alpha:&alpha];
                    return [NSString stringWithFormat:@"%@#%02X%02X%02X%02X",
                            colorSpaceDescription,
                            (int)(cyan * 255), (int)(magenta * 255), (int)(yellow * 255), (int)(black * 255)];
                }

                case NSColorSpaceModelLAB: {
                    return @"lab";  // No API for this
                }

                case NSColorSpaceModelDeviceN:
                    return @"deviceN";

                case NSColorSpaceModelIndexed:
                    return @"indexed";

                case NSColorSpaceModelPatterned:
                    return @"patterned";

                default:
                    return @"unknown";
            }
        }

        case NSColorTypeCatalog:
            return self.description;

        case NSColorTypePattern:
            return @"pattern";
    }

    return @"unknown";
}

+ (NSColor *)colorPreservingColorspaceFromString:(NSString *)s {
    if ([s hasPrefix:@"#"] && (s.length == 7 || s.length == 13)) {
        return [[self colorFromHexString:s] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    }
    if ([s hasPrefix:@"p3#"] && (s.length == 9 || s.length == 15)) {
        return [[self colorFromHexString:s] colorUsingColorSpace:[NSColorSpace displayP3ColorSpace]];
    }
    return [self colorWithString:s];
}

+ (NSColor *)colorWithString:(NSString *)s {
    if ([s hasPrefix:@"#"] && (s.length == 7 || s.length == 13)) {
        return [self colorFromHexString:s];
    }
    if ([s hasPrefix:@"p3#"] && (s.length == 9 || s.length == 15)) {
        return [self colorFromHexString:s];
    }
    NSData *data = [[[NSData alloc] initWithBase64EncodedString:s options:0] autorelease];
    if (!data.length) {
        return nil;
    }
    NSError *error = nil;
    NSKeyedUnarchiver *decoder = [[[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error] autorelease];
    if (error) {
        NSLog(@"Failed to decode color from string %@", s);
        DLog(@"Failed to decode color from string %@", s);
        return nil;
    }
    NSColor *color = [[[NSColor alloc] initWithCoder:decoder] autorelease];
    return color;
}

- (NSString *)stringValue {
    NSKeyedArchiver *coder = [[[NSKeyedArchiver alloc] initRequiringSecureCoding:YES] autorelease];
    coder.outputFormat = NSPropertyListBinaryFormat_v1_0;
    [self encodeWithCoder:coder];
    [coder finishEncoding];
    return [coder.encodedData base64EncodedStringWithOptions:0];
}

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue {
    if ([iTermAdvancedSettingsModel p3]) {
        return [NSColor colorWithDisplayP3Red:red / 255.0
                                        green:green / 255.0
                                         blue:blue / 255.0
                                        alpha:1];
    } else {
        return [NSColor colorWithSRGBRed:red / 255.0
                                   green:green / 255.0
                                    blue:blue / 255.0
                                   alpha:1];
    }
}

+ (NSColor *)it_dynamicColorForLightMode:(NSColor *)light
                                darkMode:(NSColor *)dark {
    return [NSColor colorWithName:[NSString stringWithFormat:@"iTerm%@_%@DynamicColor", light.shortDescription, dark.shortDescription] dynamicProvider:^NSColor * _Nonnull(NSAppearance *appearance) {
        if (appearance.it_isDark) {
            return dark;
        } else {
            return light;
        }
    }];
}

+ (NSColor *)it_automaticDynamicColorForLightModeColor:(NSColor *)lightModeColor {
    NSColor *darkModeColor = [lightModeColor it_darkModeCounterpart];
    return [self it_dynamicColorForLightMode:lightModeColor darkMode:darkModeColor];
}

+ (NSColor *)it_automaticDynamicColorForLightModeWhite:(CGFloat)white
                                                 alpha:(CGFloat)alpha {
    return [self it_automaticDynamicColorForLightModeColor:[NSColor colorWithWhite:white alpha:alpha]];
}

- (NSColor *)it_darkModeCounterpart {
    NSColor *rgbColor = [self colorUsingColorSpace:[NSColorSpace displayP3ColorSpace]];
    if (!rgbColor) {
        return self;
    }

    CGFloat hue;
    CGFloat saturation;
    CGFloat brightness;
    CGFloat alpha;
    [rgbColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

    CGFloat invertedBrightness = 1.0 - brightness; // Invert brightness
    return [NSColor colorWithHue:hue
                      saturation:saturation
                      brightness:invertedBrightness
                           alpha:alpha];
}

+ (void)getComponents:(CGFloat *)result
      forColorWithRed:(CGFloat)r
                green:(CGFloat)g
                 blue:(CGFloat)b
                alpha:(CGFloat)a
  perceivedBrightness:(CGFloat)t {
    /*
     Given:
     a vector c [c1, c2, c3] (the starting color)
     a vector e [e1, e2, e3] (an extreme color we are moving to, normally black or white)
     a vector A [a1, a2, a3] (the perceived brightness transform)
     a linear function f(Y)=AY (perceived brightness for color Y)
     a constant t (target perceived brightness)
     find a vector X such that F(X)=t
     and X lies on a straight line between c and e

     Define a parametric vector x(p) = [x1(p), x2(p), x3(p)]:
     x1(p) = p*e1 + (1-p)*c1
     x2(p) = p*e2 + (1-p)*c2
     x3(p) = p*e3 + (1-p)*c3

     when p=0, x=c
     when p=1, x=e

     the line formed by x(p) from p=0 to p=1 is the line from c to e.

     Our goal: find the value of p where f(x(p))=t

     We know that:
     [x1(p)]
     f(X) = AX = [a1 a2 a3] [x2(p)] = a1x1(p) + a2x2(p) + a3x3(p)
     [x3(p)]
     Expand and solve for p:
     t = a1*(p*e1 + (1-p)*c1) + a2*(p*e2 + (1-p)*c2) + a3*(p*e3 + (1-p)*c3)
     t = a1*(p*e1 + c1 - p*c1) + a2*(p*e2 + c2 - p*c2) + a3*(p*e3 + c3 - p*c3)
     t = a1*p*e1 + a1*c1 - a1*p*c1 + a2*p*e2 + a2*c2 - a2*p*c2 + a3*p*e3 + a3*c3 - a3*p*c3
     t = a1*p*e1 - a1*p*c1 + a2*p*e2 - a2*p*c2 + a3*p*e3 - a3*p*c3 + a1*c1 + a2*c2 + a3*c3
     t = p*(a2*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3) + a1*c1 + a2*c2 + a3*c3
     t - (a1*c1 + a2*c2 + a3*c3) = p*(a1*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3)
     p = (t - (a1*c1 + a2*c2 + a3*c3)) / (a1*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3)

     The PerceivedBrightness() function is a dot product between the a vector and its input, so the
     previous equation is equivalent to:
     p = (t - PerceivedBrightness(c1, c2, c3) / PerceivedBrightness(e1-c1, e2-c2, e3-c3)
     */
    const CGFloat c1 = r;
    const CGFloat c2 = g;
    const CGFloat c3 = b;

    CGFloat k;
    if (PerceivedBrightness(r, g, b) < t) {
        k = 1;
    } else {
        k = 0;
    }
    const CGFloat e1 = k;
    const CGFloat e2 = k;
    const CGFloat e3 = k;

    CGFloat p = ((t - PerceivedBrightness(c1, c2, c3)) /
                 (PerceivedBrightness(e1 - c1, e2 - c2, e3 - c3)));
    // p can be out of range for e.g., division by 0.
    p = MIN(1, MAX(0, p));

    result[0] = p * e1 + (1 - p) * c1;
    result[1] = p * e2 + (1 - p) * c2;
    result[2] = p * e3 + (1 - p) * c3;
    result[3] = a;
}

+ (NSColor *)colorForAnsi256ColorIndex:(int)index {
    double r, g, b;
    if (index >= 16 && index < 232) {
        int i = index - 16;
        r = (i / 36) ? ((i / 36) * 40 + 55) / 255.0 : 0.0;
        g = (i % 36) / 6 ? (((i % 36) / 6) * 40 + 55) / 255.0 : 0.0;
        b = (i % 6) ? ((i % 6) * 40 + 55) / 255.0 : 0.0;
    } else if (index >= 232 && index < 256) {
        int i = index - 232;
        r = g = b = (i * 10 + 8) / 255.0;
    } else {
        // The first 16 colors aren't supported here.
        return nil;
    }
    if ([iTermAdvancedSettingsModel p3]) {
        return [NSColor colorWithDisplayP3Red:r
                                        green:g
                                         blue:b
                                        alpha:1];
    } else {
        NSColor* srgb = [NSColor colorWithSRGBRed:r
                                            green:g
                                             blue:b
                                            alpha:1];
        return [srgb colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    }
}

+ (void)getComponents:(CGFloat *)result
        forComponents:(CGFloat *)mainComponents
  withContrastAgainstComponents:(CGFloat *)otherComponents
                minimumContrast:(CGFloat)minimumContrast {
    const double r = mainComponents[0];
    const double g = mainComponents[1];
    const double b = mainComponents[2];
    const double a = mainComponents[3];

    const double or = otherComponents[0];
    const double og = otherComponents[1];
    const double ob = otherComponents[2];

    double mainBrightness = PerceivedBrightness(r, g, b);
    double otherBrightness = PerceivedBrightness(or, og, ob);
    CGFloat brightnessDiff = fabs(mainBrightness - otherBrightness);

    if (brightnessDiff < minimumContrast) {
        CGFloat error = fabs(brightnessDiff - minimumContrast);
        CGFloat targetBrightness = mainBrightness;
        if (mainBrightness < otherBrightness) {
            // To increase contrast, return a color that's dimmer than mainComponents
            targetBrightness -= error;
            if (targetBrightness < 0) {
                const double alternative = otherBrightness + minimumContrast;
                const double baseContrast = otherBrightness;
                const double altContrast = MIN(alternative, 1) - otherBrightness;
                if (altContrast > baseContrast) {
                    targetBrightness = alternative;
                }
            }
        } else {
            // To increase contrast, return a color that's brighter than mainComponents
            targetBrightness += error;
            if (targetBrightness > 1) {
                const double alternative = otherBrightness - minimumContrast;
                const double baseContrast = 1 - otherBrightness;
                const double altContrast = otherBrightness - MAX(alternative, 0);
                if (altContrast > baseContrast) {
                    targetBrightness = alternative;
                }
            }
        }
        targetBrightness = MIN(MAX(0, targetBrightness), 1);

        [self getComponents:result
            forColorWithRed:r
                      green:g
                       blue:b
                      alpha:a
        perceivedBrightness:targetBrightness];
    } else {
        memmove(result, mainComponents, sizeof(CGFloat) * 4);
    }
}

- (int)nearestIndexIntoAnsi256ColorTable {
    NSColor *theColor = [self colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    int r = 5 * [theColor redComponent];
    int g = 5 * [theColor greenComponent];
    int b = 5 * [theColor blueComponent];
    return 16 + b + g * 6 + r * 36;
}

- (NSColor *)colorDimmedBy:(double)dimmingAmount towardsGrayLevel:(double)grayLevel {
    if (dimmingAmount == 0) {
        return self;
    }
    // This algorithm limits the dynamic range of colors as well as brightening
    // them. Both attributes change in proportion to the dimmingAmount.

    // Find a linear interpolation between kCenter and the requested color component
    // in proportion to 1- dimmingAmount.
    CGFloat components[4];
    [self getComponents:components];
    for (int i = 0; i < 3; i++) {
        components[i] = (1 - dimmingAmount) * components[i] + dimmingAmount * grayLevel;
    }
    return [NSColor colorWithColorSpace:self.colorSpace components:components count:4];
}

- (CGFloat)perceivedBrightness {
    NSColor *safeColor = [self colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    return PerceivedBrightness([safeColor redComponent],
                               [safeColor greenComponent],
                               [safeColor blueComponent]);
}

- (BOOL)isDark {
    return [self perceivedBrightness] < 0.5;
}

- (NSDictionary *)dictionaryValue {
    if ([iTermAdvancedSettingsModel p3]) {
        NSColor *color = [self colorUsingColorSpace:[NSColorSpace displayP3ColorSpace]];
        CGFloat red, green, blue, alpha;
        [color getRed:&red green:&green blue:&blue alpha:&alpha];
        return @{ kEncodedColorDictionaryColorSpace: kEncodedColorDictionaryP3ColorSpace,
                  kEncodedColorDictionaryRedComponent: @(red),
                  kEncodedColorDictionaryGreenComponent: @(green),
                  kEncodedColorDictionaryBlueComponent: @(blue),
                  kEncodedColorDictionaryAlphaComponent: @(alpha) };
    }
    return [self srgbDictionaryValue];
}

- (NSDictionary *)dictionaryValuePreservingColorSpace {
    DLog(@"%@", self);
    switch (self.type) {
        case NSColorTypeComponentBased:
            break;
        case NSColorTypePattern:
            DLog(@"Attempt to get dictionary value for pattern color");
            return [[NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1.0] dictionaryValuePreservingColorSpace];
        case NSColorTypeCatalog:
            DLog(@"Converting catalog color to rgb");
            return [[self colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] dictionaryValuePreservingColorSpace];
    }

    NSColorSpace *colorSpace = [self colorSpace];
    NSString *colorSpaceName;
    if ([colorSpace isEqual:[NSColorSpace sRGBColorSpace]]) {
        colorSpaceName = kEncodedColorDictionarySRGBColorSpace;
    } else if ([colorSpace isEqual:[NSColorSpace displayP3ColorSpace]]) {
        colorSpaceName = kEncodedColorDictionaryP3ColorSpace;
    } else if ([colorSpace isEqual:[NSColorSpace deviceRGBColorSpace]]) {
        colorSpaceName = kEncodedColorDictionaryCalibratedColorSpace;
    } else {
        DLog(@"Convert color in space %@ to calibrated", colorSpace);
        NSColor *deviceColor = [self colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
        if (!deviceColor) {
            DLog(@"Failed to convert %@ to device RGB color space", self);
            deviceColor = [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1.0];
        }
        return [deviceColor dictionaryValuePreservingColorSpace];
    }
    CGFloat red, green, blue, alpha;
    [self getRed:&red green:&green blue:&blue alpha:&alpha];
    return @{ kEncodedColorDictionaryColorSpace: colorSpaceName,
              kEncodedColorDictionaryRedComponent: @(red),
              kEncodedColorDictionaryGreenComponent: @(green),
              kEncodedColorDictionaryBlueComponent: @(blue),
              kEncodedColorDictionaryAlphaComponent: @(alpha) };
}

- (NSDictionary *)srgbDictionaryValue {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGFloat red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    return @{ kEncodedColorDictionaryColorSpace: kEncodedColorDictionarySRGBColorSpace,
              kEncodedColorDictionaryRedComponent: @(red),
              kEncodedColorDictionaryGreenComponent: @(green),
              kEncodedColorDictionaryBlueComponent: @(blue),
              kEncodedColorDictionaryAlphaComponent: @(alpha) };
}

- (NSColor *)colorByPremultiplyingAlphaWithColor:(NSColor *)background {
    CGFloat a[4];
    CGFloat b[4];
    [self getComponents:a];
    [background getComponents:b];
    CGFloat x[4];
    CGFloat alpha = a[3];
    for (int i = 0; i < 3; i++) {
        x[i] = a[i] * alpha + b[i] * (1 - alpha);
    }
    x[3] = b[3];
    return [NSColor colorWithColorSpace:self.colorSpace components:x count:4];
}

// Also update +colorFromHexString: when adding colorspaces here.
- (NSString *)hexString {
    NSDictionary *dict = [self dictionaryValue];
    return [NSColor hexStringForDictionary:dict];
}

- (NSString *)humanReadableDescription {
    NSDictionary *dict = [self dictionaryValue];
    NSString *space = dict[kEncodedColorDictionaryColorSpace];
    int red = [dict[kEncodedColorDictionaryRedComponent] doubleValue] * 255;
    int green = [dict[kEncodedColorDictionaryGreenComponent] doubleValue] * 255;
    int blue = [dict[kEncodedColorDictionaryBlueComponent] doubleValue] * 255;
    if (space) {
        return [NSString stringWithFormat:@"#%02x%02x%02x in color space “%@”", red, green, blue, space];
    } else {
        return [NSString stringWithFormat:@"#%02x%02x%02x", red, green, blue];
    }
}

+ (NSString *)hexStringForDictionary:(NSDictionary *)dict {
    if ([dict[kEncodedColorDictionaryColorSpace] isEqual:kEncodedColorDictionaryP3ColorSpace]) {
        int red = round([dict[kEncodedColorDictionaryRedComponent] doubleValue] * 65535);
        int green = round([dict[kEncodedColorDictionaryGreenComponent] doubleValue] * 65535);
        int blue = round([dict[kEncodedColorDictionaryBlueComponent] doubleValue] * 65535);
        return [NSString stringWithFormat:@"p3#%04x%04x%04x", red, green, blue];
    }
    int red = [dict[kEncodedColorDictionaryRedComponent] doubleValue] * 255;
    int green = [dict[kEncodedColorDictionaryGreenComponent] doubleValue] * 255;
    int blue = [dict[kEncodedColorDictionaryBlueComponent] doubleValue] * 255;
    return [NSString stringWithFormat:@"#%02x%02x%02x", red, green, blue];
}

- (NSString *)srgbHexString {
    NSDictionary *dict = [self srgbDictionaryValue];
    int red = [dict[kEncodedColorDictionaryRedComponent] doubleValue] * 255;
    int green = [dict[kEncodedColorDictionaryGreenComponent] doubleValue] * 255;
    int blue = [dict[kEncodedColorDictionaryBlueComponent] doubleValue] * 255;
    return [NSString stringWithFormat:@"#%02x%02x%02x", red, green, blue];
}

- (NSString *)hexStringPreservingColorSpace {
    NSDictionary *dict = [self dictionaryValuePreservingColorSpace];
    return [NSColor hexStringForDictionary:dict];
}

// Also update +colorWithString: when adding colorspaces here.
+ (instancetype)colorFromHexString:(NSString *)fullString {
    NSString *hexString = fullString;
    BOOL p3 = NO;
    if ([hexString hasPrefix:@"p3#"]){
        p3 = YES;
        hexString = [fullString substringFromIndex:2];
    }
    unsigned int red, green, blue;
    if (![hexString getHashColorRed:&red green:&green blue:&blue]) {
        return nil;
    }
    if (p3) {
        return [[NSColor colorWithDisplayP3Red:red / 65535.0
                                         green:green / 65535.0
                                          blue:blue / 65535.0
                                         alpha:1] it_colorInDefaultColorSpace];
    } else {
        return [[NSColor colorWithSRGBRed:red / 65535.0
                                    green:green / 65535.0
                                     blue:blue / 65535.0
                                    alpha:1] it_colorInDefaultColorSpace];
    }
}

- (NSColor *)it_colorByDimmingByAmount:(double)dimmingAmount {
    NSColor *color = self;
    double r = [color redComponent];
    double g = [color greenComponent];
    double b = [color blueComponent];
    double alpha = 1 - dimmingAmount;
    
    // Biases the input color by 1-alpha toward gray of (basis, basis, basis).
    double basis = 0.15;
    
    r = alpha * r + (1 - alpha) * basis;
    g = alpha * g + (1 - alpha) * basis;
    b = alpha * b + (1 - alpha) * basis;

    const CGFloat components[] = { r, g, b, 1 };
    return [NSColor colorWithColorSpace:self.colorSpace components:components count:4];
}

- (NSColor *)it_colorWithAppearance:(NSAppearance *)appearance {
    if (self.type != NSColorTypeCatalog) {
        return self;
    }

    static NSMutableDictionary *darkDict, *lightDict;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        darkDict = [[NSMutableDictionary alloc] init];
        lightDict = [[NSMutableDictionary alloc] init];
    });

    NSMutableDictionary *dict;
    NSString *closest = [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua, NSAppearanceNameAqua ]];
    if ([closest isEqualToString:NSAppearanceNameDarkAqua]) {
        dict = darkDict;
    } else {
        dict = lightDict;
    }

    NSColor *result = dict[self];
    if (result) {
        return result;
    }

    NSView *view = [[[SolidColorView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1) color:self] autorelease];
    view.appearance = appearance;
    NSImage *image = [view snapshot];

    NSBitmapImageRep *imageRep = [[[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]] autorelease];
    result = [imageRep colorAtX:0 y:0];

    dict[self] = result;
    return result;
}

- (NSColorSpace * _Nullable)it_colorSpace {
    @try {
        // JFC apple. colorSpace throws an exception but it's a property so it's a nice little landmine they leave for you.
        return [self colorSpace];
    } @catch (NSException *exception) {
        return nil;
    }
}

- (NSColor *)it_colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha {
    CGFloat components[] = { red, green, blue, alpha };
    return [NSColor colorWithColorSpace:self.colorSpace components:components count:4];
}

+ (NSColor *)it_colorInDefaultColorSpaceWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha {
    if ([iTermAdvancedSettingsModel p3]) {
        return [NSColor colorWithDisplayP3Red:red green:green blue:blue alpha:alpha];
    }
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha];
}

- (NSColor *)it_colorInDefaultColorSpace {
    return [self colorUsingColorSpace:[NSColorSpace it_defaultColorSpace]];
}

- (BOOL)isApproximatelyEqualToColor:(NSColor *)other epsilon:(double)e {
    NSColor *color = [other colorUsingColorSpace:self.colorSpace];
    if (fabs(self.redComponent - color.redComponent) > e ||
        fabs(self.greenComponent - color.greenComponent) > e ||
        fabs(self.blueComponent - color.blueComponent) > e ||
        fabs(self.alphaComponent - color.alphaComponent) > e) {
        return NO;
    }
    return YES;
}

- (NSColor *)blendedWithColor:(NSColor *)color weight:(CGFloat)weight {
    if (!color) {
        return self;
    }
    // Convert colors to LAB color space for perceptual blending
    CGFloat whitePoint[3] = {0.95047, 1.0, 1.08883}; // D50 white point
    CGFloat blackPoint[3] = {0.0, 0.0, 0.0};
    CGFloat range[4] = {-128.0, 127.0, -128.0, 127.0};
    CGColorSpaceRef labColorSpace = CGColorSpaceCreateLab(whitePoint, blackPoint, range);

    if (!labColorSpace) {
        return self;
    }

    NSColorSpace *nslab = [[[NSColorSpace alloc] initWithCGColorSpace:labColorSpace] autorelease];
    CIColor *ciColor1 = [[[CIColor alloc] initWithColor:[self colorUsingColorSpace:nslab]] autorelease];
    CIColor *ciColor2 = [[[CIColor alloc] initWithColor:[color colorUsingColorSpace:nslab]] autorelease];
    CIColor *ciBlendedColor;

    // Get LAB components of each color
    const CGFloat l1 = ciColor1.components[0];
    const CGFloat a1 = ciColor1.components[1];
    const CGFloat b1 = ciColor1.components[2];

    const CGFloat l2 = ciColor2.components[0];
    const CGFloat a2 = ciColor2.components[1];
    const CGFloat b2 = ciColor2.components[2];

    // Blend the colors by weighting their LAB components
    CGFloat blendedL = (1 - weight) * l1 + weight * l2;
    CGFloat blendedA = (1 - weight) * a1 + weight * a2;
    CGFloat blendedB = (1 - weight) * b1 + weight * b2;

    // Create a new CIColor object in LAB color space
    CGFloat components[4] = {blendedL, blendedA, blendedB, 1.0};
    CGColorRef cgColor = CGColorCreate(labColorSpace, components);
    if (!cgColor) {
        CGColorSpaceRelease(labColorSpace);
        return self;
    }
    ciBlendedColor = [[[CIColor alloc] initWithColor:[NSColor colorWithCGColor:cgColor]] autorelease];
    CGColorRelease(cgColor);
    CGColorSpaceRelease(labColorSpace);

    // Convert the blended LAB color to NSColor object for display
    return [[NSColor colorWithCIColor:ciBlendedColor] colorUsingColorSpace:self.colorSpace];
}

- (vector_float4)vector {
    return simd_make_float4(self.redComponent,
                            self.greenComponent,
                            self.blueComponent,
                            self.alphaComponent);
}

@end

@implementation NSColorSpace(iTerm)
+ (instancetype)it_defaultColorSpace {
    if ([iTermAdvancedSettingsModel p3]) {
        return [NSColorSpace displayP3ColorSpace];
    }
    return [NSColorSpace sRGBColorSpace];
}
@end
