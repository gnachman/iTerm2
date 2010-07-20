//
//  GrowlImageAdditions.m
//  Display Plugins
//
//  Created by Jorge Salvador Caffarena on 20/09/04.
//  Copyright 2004-2005 The Growl Project. All rights reserved.
//

#import "GrowlImageAdditions.h"

@implementation NSImage (GrowlImageAdditions)

- (void) drawScaledInRect:(NSRect)targetRect operation:(NSCompositingOperation)operation fraction:(float)f {
	[self adjustSizeToDrawAtSize:targetRect.size];
	NSRect imageRect;
	imageRect.origin.x = 0.0f;
	imageRect.origin.y = 0.0f;
	imageRect.size = [self size];
	if (imageRect.size.width > targetRect.size.width || imageRect.size.height > targetRect.size.height) {
		// make sure the icon isn't too large. If it is, scale it down
		if (imageRect.size.width > imageRect.size.height) {
			float oldHeight = targetRect.size.height;
			targetRect.size.height = oldHeight / imageRect.size.width * imageRect.size.height;
			targetRect.origin.y = floorf(targetRect.origin.y - (targetRect.size.height - oldHeight) * 0.5f);
		} else if (imageRect.size.width < imageRect.size.height) {
			float oldWidth = targetRect.size.width;
			targetRect.size.width = oldWidth / imageRect.size.height * imageRect.size.width;
			targetRect.origin.x = floorf(targetRect.origin.x - (targetRect.size.width - oldWidth) * 0.5f);
		}

		[self setScalesWhenResized:YES];
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
	} else {
		// center image if it is too small
		if (imageRect.size.width < targetRect.size.width) {
			targetRect.origin.x += ceilf((targetRect.size.width - imageRect.size.width) * 0.5f);
		}
	 	if (imageRect.size.height < targetRect.size.height) {
			targetRect.origin.y += ceilf((targetRect.size.height - imageRect.size.height) * 0.5f);
		}
		targetRect.size = imageRect.size;
	}

	[self drawInRect:targetRect fromRect:imageRect operation:operation fraction:f];
}

- (NSSize) adjustSizeToDrawAtSize:(NSSize)theSize {
	NSImageRep *bestRep = [self bestRepresentationForSize:theSize];
	[self setSize:[bestRep size]];
	return [bestRep size];
}

- (NSImageRep *) bestRepresentationForSize:(NSSize)theSize {
	NSImageRep *bestRep = [self representationOfSize:theSize];
	if (!bestRep) {
		NSArray *reps = [self representations];
		// ***warning   * handle other sizes
		float repDistance = 65536.0f;
		// ***warning   * this is totally not the highest, but hey...
		NSImageRep *thisRep;
		float thisDistance;
		NSEnumerator *enumerator = [reps objectEnumerator];
		while ((thisRep = [enumerator nextObject])) {
			thisDistance = theSize.width - [thisRep size].width;
			if (repDistance < 0.0f && thisDistance > 0.0f)
				continue;
			if (ABS(thisDistance) < ABS(repDistance) || (thisDistance < 0.0f && repDistance > 0.0f)) {
				repDistance = thisDistance;
				bestRep = thisRep;
			}
		}
	}
	if (!bestRep)
		bestRep = [self bestRepresentationForDevice:nil];

	return bestRep;
}

- (NSImageRep *) representationOfSize:(NSSize)theSize {
	NSArray *reps = [self representations];
	NSEnumerator *enumerator = [reps objectEnumerator];
	NSImageRep *rep;
	while ((rep = [enumerator nextObject]))
		if (NSEqualSizes([rep size], theSize))
			break;
	return rep;
}

@end
