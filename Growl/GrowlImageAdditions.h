//
//  GrowlImageAdditions.h
//  Display Plugins
//
//  Created by Jorge Salvador Caffarena on 20/09/04.
//  Copyright 2004-2005 The Growl Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSImage (GrowlImageAdditions)

- (void) drawScaledInRect:(NSRect)targetRect operation:(NSCompositingOperation)operation fraction:(float)f;
- (NSSize) adjustSizeToDrawAtSize:(NSSize)theSize;
- (NSImageRep *) bestRepresentationForSize:(NSSize)theSize;
- (NSImageRep *) representationOfSize:(NSSize)theSize;

@end
