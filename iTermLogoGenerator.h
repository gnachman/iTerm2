//
//  iTermLogoGenerator.h
//  iTerm
//
//  Created by George Nachman on 7/11/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermLogoGenerator : NSObject

@property(nonatomic, retain) NSColor *textColor;
@property(nonatomic, retain) NSColor *cursorColor;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *tabColor;

- (NSImage *)generatedImage;

@end
