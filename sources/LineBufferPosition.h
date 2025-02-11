#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LineBufferPosition : NSObject

// Absolute position - bytes from start of line buffer plus total number of bytes that ever have
// been dropped.
@property(nonatomic) long long absolutePosition;

// Number of lines past that absolute position because empty lines aren't taken into account in
// absolute position.
@property(nonatomic) int yOffset;

// Indicates if the position is at the end of the line (on a hard-wrapped line, one or more
// nulls that aren't stored in the line buffer appear on the screen, and a position can be either
// on the text or at the end of the wrapped line).
@property(nonatomic) BOOL extendsToEndOfLine;

@property (nonatomic, readonly) NSString *compactStringValue;

+ (instancetype)fromCompactStringValue:(NSString *)value;

+ (LineBufferPosition *)position;
- (LineBufferPosition *)predecessor;

- (BOOL)isEqualToLineBufferPosition:(LineBufferPosition * _Nullable)other;
- (NSComparisonResult)compare:(LineBufferPosition * _Nullable)other;

- (LineBufferPosition *)advancedBy:(int)cells;

@end

@interface LineBufferPositionRange : NSObject
@property(nonatomic, retain) LineBufferPosition *start;
@property(nonatomic, retain) LineBufferPosition *end;
@end

NS_ASSUME_NONNULL_END
