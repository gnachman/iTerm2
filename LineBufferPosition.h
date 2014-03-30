#import <Foundation/Foundation.h>

@interface LineBufferPosition : NSObject {
    long long absolutePosition_;
    int yOffset_;
    BOOL extendsToEndOfLine_;
}

// Absolute position - bytes from start of line buffer plus total number of bytes that ever have
// been dropped.
@property(nonatomic, assign) long long absolutePosition;

// Number of lines past that absolute position because empty lines aren't taken into account in
// absolute position.
@property(nonatomic, assign) int yOffset;

// Indicates if the position is at the end of the line (on a hard-wrapped line, one or more
// nulls that aren't stored in the line buffer appear on the screen, and a position can be either
// on the text or at the end of the wrapped line).
@property(nonatomic, assign) BOOL extendsToEndOfLine;

+ (LineBufferPosition *)position;
- (LineBufferPosition *)predecessor;

@end

@interface LineBufferPositionRange : NSObject
@property(nonatomic, retain) LineBufferPosition *start;
@property(nonatomic, retain) LineBufferPosition *end;
@end
