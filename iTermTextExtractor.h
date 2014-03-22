//
//  iTermTextExtractor.h
//  iTerm
//
//  Created by George Nachman on 2/17/14.
//
//

#import <Foundation/Foundation.h>
#import "PTYTextViewDataSource.h"
#import "ScreenChar.h"

typedef enum {
    // Any kind of white space.
    kTextExtractorClassWhitespace,

    // Characters that belong to a word.
    kTextExtractorClassWord,

    // Unset character
    kTextExtractorClassNull,

    // Non-alphanumeric, non-whitespace, non-word, not double-width filler.
    // Miscellaneous symbols, etc.
    kTextExtractorClassOther
} iTermTextExtractorClass;

typedef enum {
    kiTermTextExtractorNullPolicyFromStartToFirst,
    kiTermTextExtractorNullPolicyFromLastToEnd,
    kiTermTextExtractorNullPolicyTreatAsSpace
} iTermTextExtractorNullPolicy;

@interface iTermTextExtractor : NSObject

@property(nonatomic, assign) VT100GridRange logicalWindow;
@property(nonatomic, readonly) BOOL hasLogicalWindow;

// Characters that divide words.
+ (NSCharacterSet *)wordSeparatorCharacterSet;

+ (instancetype)textExtractorWithDataSource:(id<PTYTextViewDataSource>)dataSource;
- (id)initWithDataSource:(id<PTYTextViewDataSource>)dataSource;
- (void)restrictToLogicalWindowIncludingCoord:(VT100GridCoord)coord;

// Returns the range of a word (string of characters belonging to the same class) at a location. If
// there is a paren or paren-like character at location, it tries to return the range of the
// parenthetical, even if there are mixed classes. Returns (-1, -1, -1, -1) if location is out of
// bounds.
- (VT100GridWindowedRange)rangeForWordAt:(VT100GridCoord)location;

// Returns the string for the character at a screen location.
- (NSString *)stringForCharacterAt:(VT100GridCoord)location;
- (NSString *)stringForCharacter:(screen_char_t)theChar;

// Uses the provided smart selection |rules| to perform a smart selection at |location|. If
// |actionRequired| is set then rules without an action are ignored. If a rule is matched, it is
// returned and |range| is set to the range of matching characters.
- (NSDictionary *)smartSelectionAt:(VT100GridCoord)location
                         withRules:(NSArray *)rules
                    actionRequired:(BOOL)actionRequired
                             range:(VT100GridWindowedRange *)range
                  ignoringNewlines:(BOOL)ignoringNewlines;

// Returns the range of the whole wrapped line including |coord|.
- (VT100GridWindowedRange)rangeForWrappedLineEncompassing:(VT100GridCoord)coord
                                  respectContinuations:(BOOL)respectContinuations;

// Returns the class for a character.
- (iTermTextExtractorClass)classForCharacter:(screen_char_t)theCharacter;

// If the character at |location| is a paren, brace, or bracket, and there is a matching
// open/close paren/brace/bracket, the range from the opening to closing paren/brace/bracket is
// returned. If that is not the case, then (-1, -1, -1, -1) is returned.
- (VT100GridWindowedRange)rangeOfParentheticalSubstringAtLocation:(VT100GridCoord)location;

// Returns next/previous coordinate. Returns first/last legal coord if none exists.
- (VT100GridCoord)successorOfCoord:(VT100GridCoord)coord;
- (VT100GridCoord)predecessorOfCoord:(VT100GridCoord)coord;
- (VT100GridCoord)coord:(VT100GridCoord)coord plus:(int)delta;

// block should return YES to stop searching and use the coordinate it was passed as the result.
- (VT100GridCoord)searchFrom:(VT100GridCoord)start
                     forward:(BOOL)forward
      forCharacterMatchingFilter:(BOOL (^)(screen_char_t, VT100GridCoord))block;

// Returns content in the specified range, ignoring hard newlines. If |forward| is set then content
// is captured up to the first null; otherwise, content after the last null in the range is returned.
- (NSString *)contentInRange:(VT100GridWindowedRange)range
                  nullPolicy:(iTermTextExtractorNullPolicy)nullPolicy
                         pad:(BOOL)pad
          includeLastNewline:(BOOL)includeLastNewline
      trimTrailingWhitespace:(BOOL)trimSelectionTrailingSpaces
                cappedAtSize:(int)maxBytes;

- (void)enumerateCharsInRange:(VT100GridWindowedRange)range
                    charBlock:(BOOL (^)(screen_char_t theChar, VT100GridCoord coord))charBlock
                     eolBlock:(BOOL (^)(unichar code, int numPreceedingNulls, int line))eolBlock;

- (BOOL)isTabFillerOrphanAt:(VT100GridCoord)coord;

- (int)lengthOfLine:(int)line;

// Finds text before or at+after |coord|. If |respectHardNewlines|, then the whole wrapped line is
// returned up to/from |coord|. If not, then 10 lines are returned.
- (NSString *)wrappedStringAt:(VT100GridCoord)coord
                      forward:(BOOL)forward
          respectHardNewlines:(BOOL)respectHardNewlines;

- (NSAttributedString *)attributedContentInRange:(VT100GridWindowedRange)range
                                             pad:(BOOL)pad
                               attributeProvider:(NSDictionary *(^)(screen_char_t))attributeProvider;

- (screen_char_t)characterAt:(VT100GridCoord)coord;

@end
