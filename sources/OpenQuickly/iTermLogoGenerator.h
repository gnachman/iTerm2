#import <Cocoa/Cocoa.h>

// Generates a small iTerm2 logo with custom text, cursor, background, and tab
// colors. All color properties must be set before a logo can be generated.
@interface iTermLogoGenerator : NSObject

@property(nonatomic, retain) NSColor *textColor;
@property(nonatomic, retain) NSColor *cursorColor;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *tabColor;

- (NSImage *)generatedImage;

@end
