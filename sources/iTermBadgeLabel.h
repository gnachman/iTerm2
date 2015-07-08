//
//  iTermBadgeLabel.h
//  iTerm2
//
//  Created by George Nachman on 7/7/15.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermBadgeLabel : NSObject

// Color for badge text fill
@property(nonatomic, retain) NSColor *fillColor;

// Color for badge text outline
@property(nonatomic, retain) NSColor *backgroundColor;

// Badge text
@property(nonatomic, copy) NSString *stringValue;

// Size of containing view
@property(nonatomic, assign) NSSize viewSize;

// Lazily computed image.
@property(nonatomic, readonly) NSImage *image;

// If true then the inputs to |image| have changed. Set by other setters, and
// can also be explicitly set to invalidate the image.
@property(nonatomic, assign, getter=isDirty) BOOL dirty;

@end
