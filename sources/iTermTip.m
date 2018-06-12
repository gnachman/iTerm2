//
//  iTermTip.m
//  iTerm2
//
//  Created by George Nachman on 6/18/15.
//
//

#import "iTermTip.h"

NSString *const kTipTitleKey = @"title";
NSString *const kTipIdentifierKey = @"key";
NSString *const kTipBodyKey = @"body";
NSString *const kTipUrlKey = @"url";

@interface iTermTip()

@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *body;
@property(nonatomic, copy) NSString *url;

@end

@implementation iTermTip

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
                        identifier:(NSString *)identifier {
  self = [super init];
  if (self) {
    self.identifier = identifier;
    self.title = dictionary[kTipTitleKey];
    self.body = dictionary[kTipBodyKey];
    self.url = dictionary[kTipUrlKey];
  }
  return self;
}

- (NSAttributedString *)attributedString {
    NSString *(^escape)(NSString *) = ^NSString *(NSString *xml) {
        return [[xml stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
                stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    };
    NSString *link = self.url ? [NSString stringWithFormat:@"<p><a href=\"%@\">Learn More</a></p>", self.url] : @"";
    NSString *htmlString = [NSString stringWithFormat:@"<h1>%@</h1><p>%@</p>%@",
                            escape(self.title),
                            escape(self.body),
                            link];
    return [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUTF8StringEncoding]
                                            options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                                                       NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding) }
                                 documentAttributes:nil
                                              error:NULL];
}

@end
