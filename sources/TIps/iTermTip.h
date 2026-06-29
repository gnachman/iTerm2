//
//  iTermTip.h
//  iTerm2
//
//  Created by George Nachman on 6/18/15.
//
//

#import <Cocoa/Cocoa.h>

// Dictionary keys
extern NSString *const kTipTitleKey;
extern NSString *const kTipBodyKey;
extern NSString *const kTipUrlKey;

// A tip of the day.
@interface iTermTip : NSObject

@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *body;
@property(nonatomic, readonly) NSString *url;
@property(nonatomic, readonly) NSAttributedString *attributedString;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary identifier:(NSString *)identifier;

@end

