//
//  iTermImageWell.m
//  iTerm2
//
//  Created by George Nachman on 12/17/14.
//
//

#import "iTermImageWell.h"

@implementation iTermImageWell

- (BOOL)performDragOperation:(id<NSDraggingInfo>)draggingInfo {
    if (![super performDragOperation:draggingInfo]) {
        return NO;
    }

    NSPasteboard *pasteboard = [draggingInfo draggingPasteboard];
    NSString *theString = NULL;
#if 0
    [pasteboard stringForType:NSFilenamesPboardType];
#else
    // Use the new type for file URLs
    NSArray *classes = [[NSArray alloc] initWithObjects:[NSURL class], nil];
    NSDictionary *options = [NSDictionary dictionary];

    // Check if the pasteboard contains a valid URL
    if ([pasteboard canReadObjectForClasses:classes options:options]) {
        NSArray *urls = [pasteboard readObjectsForClasses:classes options:options];
        if (urls != nil && [urls count] > 0) {
            // Assuming you want the first URL
            NSURL *firstUrl = [urls objectAtIndex:0];
            theString = [firstUrl absoluteString];
            // Use theString as needed
        }
    }
#endif

    if (theString != NULL) {
        NSData *data = [theString dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *filenames =
            [NSPropertyListSerialization propertyListWithData:data
                                                      options:NSPropertyListImmutable
                                                       format:nil
                                                        error:nil];

        if (filenames.count) {
            [_delegate imageWellDidPerformDropOperation:self filename:filenames[0]];
        }
    }

    return YES;
}

// If we don't override mouseDown: then mouseUp: never gets called.
- (void)mouseDown:(NSEvent *)theEvent {
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 2) {
        [_delegate imageWellDidClick:self];
    }
}

@end
