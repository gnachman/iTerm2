//
//  iTermTip.h
//  iTerm2
//
//  Created by George Nachman on 6/18/15.
//
//

#import <Foundation/Foundation.h>

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

- (instancetype)initWithDictionary:(NSDictionary *)dictionary identifier:(NSString *)identifier;

@end

