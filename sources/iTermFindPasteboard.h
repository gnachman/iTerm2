//
//  iTermFindPasteboard.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermFindPasteboard : NSObject
@property (null_resettable, nonatomic, copy) NSString *stringValue;

+ (instancetype)sharedInstance;
- (void)updateObservers:(id _Nullable)sender;
- (void)addObserver:(id)observer block:(void (^)(id sender, NSString *newValue))block;

@end

NS_ASSUME_NONNULL_END
