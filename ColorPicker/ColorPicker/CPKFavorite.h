#import <Foundation/Foundation.h>

// The UTI for CPKFavorite.
extern NSString *const kCPKFavoriteUTI;

/** Represents a saved color. */
@interface CPKFavorite : NSObject <NSPasteboardReading, NSPasteboardWriting, NSSecureCoding>

+ (instancetype)favoriteWithColor:(NSColor *)color name:(NSString *)name;

/** The favorite color's name. May be nil. */
@property(nonatomic) NSString *name;

/** THe color. */
@property(nonatomic) NSColor *color;

/** A unique identifier. */
@property(nonatomic, readonly) NSString *identifier;

@end
