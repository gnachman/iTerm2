//  From http://www.cocoadev.com/index.pl?NSImageCategory
//  NSBitmapImageRep+CoreImage.m
//  iTerm2

#import <QuartzCore/QuartzCore.h>
#import "NSBitmapImageRep+CoreImage.h"
#import "NSImage+CoreImage.h"

#define CIIMAGE_PADDING 16.0f

@implementation NSBitmapImageRep (CoreImage)

- (void)drawAtPoint: (NSPoint)point fromRect: (NSRect)fromRect coreImageFilter: (NSString *)filterName arguments: (NSDictionary *)arguments {
    NSAutoreleasePool *pool;
    CIFilter *filter;
    CIImage *before;
    CIImage *after;
    CIContext *ciContext;
    CGContextRef cgContext;

    pool = [[NSAutoreleasePool alloc] init];
    before = nil;

    @try {
        before = [[CIImage alloc] initWithBitmapImageRep: self];
        if (before) {
            filter = [CIFilter filterWithName: filterName];
            [filter setDefaults];
            if (arguments)
                [filter setValuesForKeysWithDictionary: arguments];
            [filter setValue: before forKey: @"inputImage"];
        } else {
            filter = nil;
        }

        after = [filter valueForKey: @"outputImage"];
        if (after) {
            if (![[arguments objectForKey: @"gt_noRenderPadding"] boolValue]) {
                /* Add a wide berth to the bounds -- the padding can be turned
                 off by passing an NSNumber with a YES value in the argument
                 "gt_noRenderPadding" in the argument dictionary. */
                fromRect.origin.x -= CIIMAGE_PADDING;
                fromRect.origin.y -= CIIMAGE_PADDING;
                fromRect.size.width += CIIMAGE_PADDING * 2.0f;
                fromRect.size.height += CIIMAGE_PADDING * 2.0f;
                point.x -= CIIMAGE_PADDING;
                point.y -= CIIMAGE_PADDING;
            }

            cgContext = CGContextRetain((CGContextRef)[[NSGraphicsContext currentContext] graphicsPort]);
            if (cgContext) {
                ciContext = [CIContext contextWithCGContext: cgContext options: nil];
                [ciContext
                 drawImage:     after
                 atPoint:       *(CGPoint *)(&point)
                 fromRect:      *(CGRect *)(&fromRect)];
                CGContextRelease(cgContext);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"exception encountered during core image filtering: %@", e);
    } @finally {
        [before release];
    }

    [pool release];
}
@end
