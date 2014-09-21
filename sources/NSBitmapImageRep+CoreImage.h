//  From http://www.cocoadev.com/index.pl?NSImageCategory
//
//  NSBitmapImageRep+CoreImage.h
//  iTerm2
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface NSBitmapImageRep (CoreImage)
/* Draws the specified image representation using Core Image. */
- (void)drawAtPoint:(NSPoint)point
           fromRect:(NSRect)fromRect
    coreImageFilter:(NSString *)filterName
          arguments:(NSDictionary *)arguments;
@end
