//
//  iTermSwiftyStringParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/13/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// NOTE: This supports nested inline expressions. Callbacks are only inovked for topmost literals
// and expressions. So a string like:
//
// A\(B("C\(D("E"))"))
//
// Will get two callbacks:
// 1. LITERAL: A (literal)
// 2. EXPRESSION: B("C\(D("E"))")
//
// When building a syntax tree, you'll see that the argument to B takes a string which should be
// parsed again.
@interface iTermSwiftyStringParser : NSObject

@property (nonatomic, readonly) NSString *string;

// Parsing stops at the first top-level unescaped ". If this is set and none is found then
// enumerateSwiftySubstringsWithBlock: returns NSNotFound.
@property (nonatomic) BOOL stopAtUnescapedQuote;

// Don't complain if a string is truncated.
@property (nonatomic) BOOL tolerateTruncation;
@property (nonatomic, readonly) BOOL wasTruncated;
@property (nonatomic, readonly) BOOL wasTruncatedInLiteral;

- (instancetype)initWithString:(NSString *)string NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// If tolerateTruncation is YES then the index of the  beginning of the last expression or literal
// is returned. In this case, wasTruncated gets set to YES and wasTruncatedInLiteral gets set too.
// If stopAtUnescapedQuote is NO then truncation can only be in expressions, not literals.
// Non literals may contain swifty strings.
- (NSInteger)enumerateSwiftySubstringsWithBlock:(void (^ _Nullable)(NSUInteger index,
                                                                    NSString *substring,
                                                                    BOOL isLiteral,
                                                                    BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
