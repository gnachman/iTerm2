//
//  iTermLocatedString.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/20.
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

@class iTermGridCoordArray;

NS_ASSUME_NONNULL_BEGIN

// A string with an array of coords that is 1:1 with the UTF-16 codepoints in `string` giving their
// locations in history.
@interface iTermLocatedString : NSObject
@property (nonatomic, readonly) NSString *string;
@property (nonatomic, readonly) iTermGridCoordArray *gridCoords;
@property (nonatomic, readonly) NSInteger length;

- (instancetype)initWithString:(NSString *)string gridCoords:(iTermGridCoordArray *)gridCoords;

- (void)prependString:(NSString *)string at:(VT100GridCoord)coord;
- (void)appendString:(NSString *)string at:(VT100GridCoord)coord;
- (void)appendLocatedString:(iTermLocatedString *)string;
- (void)erase;
- (void)dropFirst:(NSInteger)count;
- (void)trimTrailingWhitespace;
- (void)removeOcurrencesOfString:(NSString *)string;

// Preserves the location, even if replacement is not the same length
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)replacement;
- (NSInteger)offsetOfLineNumber:(int)lineNumber;

@end

@interface iTermLocatedAttributedString : iTermLocatedString
@property (nonatomic, readonly) NSAttributedString *attributedString;

- (void)appendString:(NSString *)string
      withAttributes:(NSDictionary *)attributes
                  at:(VT100GridCoord)coord;

- (void)appendAttributedString:(NSAttributedString *)attributedString
                            at:(VT100GridCoord)coord;

@end

NS_ASSUME_NONNULL_END
