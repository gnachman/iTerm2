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

- (void)dealloc {
  [_identifier release];
  [_title release];
  [_body release];
  [_url release];
  [super dealloc];
}

@end

