//
//  iTermFindPasteboard.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermFindPasteboard : NSObject
@property (null_resettable, nonatomic, copy, readonly) NSString *stringValue;

+ (instancetype)sharedInstance;
- (void)updateObservers:(id _Nullable)sender internallyGenerated:(BOOL)internallyGenerated;
- (void)addObserver:(id)observer block:(void (^)(id sender, NSString *newValue, BOOL internallyGenerated))block;
- (void)setStringValueUnconditionally:(nullable NSString *)stringValue;
- (BOOL)setStringValueIfAllowed:(nullable NSString *)stringValue;

@end

NS_ASSUME_NONNULL_END
