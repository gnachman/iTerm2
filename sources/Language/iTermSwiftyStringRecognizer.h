//
//  iTermSwiftyStringRecognizer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import <CoreParse/CoreParse.h>
#import "iTermQuotedRecognizer.h"

@interface iTermSwiftyStringToken : CPQuotedToken

@property (nonatomic, readonly) BOOL truncated;
@property (nonatomic, readonly) BOOL endsWithLiteral;
@property (nonatomic, copy, readonly) NSString *truncatedPart;

@end

// Recognizes <<"Foo">> or <<"Foo \(>>.
@interface iTermSwiftyStringRecognizer : iTermQuotedRecognizer

@property (nonatomic, readonly) BOOL tolerateTruncation;

- (id)initWithStartQuote:(NSString *)startQuote
                endQuote:(NSString *)endQuote
          escapeSequence:(NSString *)escapeSequence
           maximumLength:(NSUInteger)maximumLength
                    name:(NSString *)name
      tolerateTruncation:(BOOL)tolerateTruncation;

@end
