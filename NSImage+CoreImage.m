//  From http://www.cocoadev.com/index.pl?NSImageCategory
//
//  NSImage+CoreImage.m
//  iTerm2

#import "NSImage+CoreImage.h"
#import "NSBitmapImageRep+CoreImage.h"

@implementation NSImage (CoreImage)
- (void)drawAtPoint: (NSPoint)point fromRect: (NSRect)fromRect coreImageFilter: (NSString *)filterName arguments: (NSDictionary *)arguments {
    NSAutoreleasePool *pool;
    NSBitmapImageRep *rep;

    pool = [[NSAutoreleasePool alloc] init];

    if (filterName) {
        rep = [self bitmapImageRepresentation];
        [rep drawAtPoint:point
                fromRect:fromRect
         coreImageFilter:filterName
               arguments:arguments];
    } else {
        /* bypass core image if no filter is specified */
        [self drawAtPoint:point
                 fromRect:fromRect
                operation:NSCompositeSourceOver
                 fraction:1.0f];
    }

    [pool release];
}

- (NSBitmapImageRep *)bitmapImageRepresentation {
    NSImageRep *rep;
    NSEnumerator *e;
    Class bitmapImageRep;

    bitmapImageRep = [NSBitmapImageRep class];
    e = [[self representations] objectEnumerator];
    while ((rep = [e nextObject]) != nil) {
        if ([rep isKindOfClass: bitmapImageRep])
            break;
        rep = nil;
    }

    if (!rep)
        rep = [NSBitmapImageRep imageRepWithData: [self TIFFRepresentation]];

    return (NSBitmapImageRep *)rep;
}

@end
