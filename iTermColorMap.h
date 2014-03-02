//
//  iTermColorMap.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Cocoa/Cocoa.h>

// This would be an enum except lldb doesn't handle enums very well.
// (lldb) po [_colorMap colorForKey:kColorMapBackground]
// error: use of undeclared identifier 'kColorMapBackground'
// error: 1 errors parsing expression
// TODO: When this is fixed, change it into an enum.

typedef int iTermColorMapKey;

extern const int kColorMapForeground;
extern const int kColorMapBackground;
extern const int kColorMapBold;
extern const int kColorMapSelection;
extern const int kColorMapSelectedText;
extern const int kColorMapCursor;
extern const int kColorMapCursorText;
extern const int kColorMapInvalid;
// This value plus 0...255 are accepted.
extern const int kColorMap8bitBase;
// This value plus 0...2^24-1 are accepted as read-only keys. These must be the highest-valued keys.
extern const int kColorMap24bitBase;

@class iTermColorMap;

@protocol iTermColorMapDelegate <NSObject>

- (void)colorMap:(iTermColorMap *)colorMap didChangeColorForKey:(iTermColorMapKey)theKey;
- (void)colorMap:(iTermColorMap *)colorMap dimmingAmountDidChangeTo:(double)dimmingAmount;

@end

@interface iTermColorMap : NSObject

@property(nonatomic, assign) BOOL dimOnlyText;
@property(nonatomic, assign) double dimmingAmount;
@property(nonatomic, assign) id<iTermColorMapDelegate> delegate;

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue;

- (void)setColor:(NSColor *)theColor forKey:(iTermColorMapKey)theKey;
- (NSColor *)colorForKey:(iTermColorMapKey)theKey;
- (NSColor *)dimmedColorForKey:(iTermColorMapKey)theKey;
- (NSColor *)dimmedColorForColor:(NSColor *)theColor;
- (void)invalidateCache;

@end
