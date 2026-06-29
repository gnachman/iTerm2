#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    double percentDifferent;
    double maxDifference;
    double variance;
    NSUInteger totalPixels;
    NSUInteger differentPixels;
} iTermImageComparisonResult;

@interface iTermImageComparison : NSObject

// Compare two images by perceived brightness. Generates a diff image at diffPath.
// Red = difference, green = similarity, grayscale = matching pixels.
+ (iTermImageComparisonResult)compareImage:(NSImage *)image1
                                 withImage:(NSImage *)image2
                             diffImagePath:(nullable NSString *)diffPath;

@end

NS_ASSUME_NONNULL_END
