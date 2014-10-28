//  From http://www.cocoadev.com/index.pl?NSImageCategory
//
//  NSImage+CoreImage.h
//  iTerm2

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface NSImage (CoreImage)
/* Draws the specified image using Core Image. */
- (void)drawAtPoint: (NSPoint)point fromRect: (NSRect)fromRect coreImageFilter: (NSString *)filterName arguments: (NSDictionary *)arguments;

/* Gets a bitmap representation of the image, or creates one if the image does not have any. */
- (NSBitmapImageRep *)bitmapImageRepresentation;
@end

