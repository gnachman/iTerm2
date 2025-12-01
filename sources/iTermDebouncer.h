//
//  iTermDebouncer.h
//  iTerm2SharedARC
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermDebouncer : NSObject

- (instancetype)initWithCallback:(void (^)(NSString *query))callback NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)updateQuery:(NSString *)query;
- (void)owningViewDidBecomeFirstResponder;

@end

NS_ASSUME_NONNULL_END
