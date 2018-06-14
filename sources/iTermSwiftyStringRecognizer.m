//
//  iTermSwiftyStringRecognizer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import "iTermSwiftyStringRecognizer.h"

#import "iTermSwiftyStringParser.h"
#import "NSStringITerm.h"

@interface iTermSwiftyStringToken()

@property (nonatomic, readwrite) BOOL truncated;
@property (nonatomic, readwrite) BOOL endsWithLiteral;
@property (nonatomic, readwrite) NSString *truncatedPart;

@end

@implementation iTermSwiftyStringToken
@end

@implementation iTermSwiftyStringRecognizer

- (id)initWithStartQuote:(NSString *)startQuote
                endQuote:(NSString *)endQuote
          escapeSequence:(NSString *)escapeSequence
           maximumLength:(NSUInteger)maximumLength
                    name:(NSString *)name
      tolerateTruncation:(BOOL)tolerateTruncation {
    self = [super initWithStartQuote:startQuote
                            endQuote:endQuote
                      escapeSequence:escapeSequence
                       maximumLength:maximumLength
                                name:name];
    if (self) {
        _tolerateTruncation = tolerateTruncation;
    }
    return self;
}

- (CPToken *)recogniseTokenInString:(NSString *)tokenString currentTokenPosition:(NSUInteger *)tokenPosition
{
    NSString *substring = [tokenString substringFromIndex:*tokenPosition];
    if (![substring hasPrefix:self.startQuote]) {
        return nil;
    }

    substring = [substring substringFromIndex:self.startQuote.length];
    iTermSwiftyStringParser *parser = [[iTermSwiftyStringParser alloc] initWithString:substring];
    parser.stopAtUnescapedQuote = YES;
    parser.tolerateTruncation = _tolerateTruncation;
    NSUInteger index = [parser enumerateSwiftySubstringsWithBlock:nil];
    if (index == NSNotFound) {
        return nil;
    }

    NSUInteger end;
    if (parser.wasTruncated) {
        end = substring.length;
    } else {
        end = index;
    }
    *tokenPosition += end + self.startQuote.length + self.endQuote.length;
    iTermSwiftyStringToken *token = [[iTermSwiftyStringToken alloc] initWithContent:[substring substringToIndex:end]
                                                                          quoteType:self.startQuote
                                                                               name:[self name]];
    if (parser.wasTruncated) {
        token.endsWithLiteral = parser.wasTruncatedInLiteral;
        token.truncatedPart = [substring substringFromIndex:index];
    }

    return token;
}

@end
