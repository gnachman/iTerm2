//
//  iTermStatusBarLayout.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarComponent.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarLayout;

@protocol iTermStatusBarLayoutDelegate<NSObject>

- (void)statusBarLayoutDidChange:(iTermStatusBarLayout *)layout;

@end

@interface iTermStatusBarLayout : NSObject<NSSecureCoding>

@property (nonatomic, weak) id<iTermStatusBarLayoutDelegate> delegate;
@property (nonatomic, strong) NSArray<id<iTermStatusBarComponent>> *components;

- (instancetype)initWithComponents:(NSArray<id<iTermStatusBarComponent>> *)components NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDictionary:(NSDictionary *)layout;

- (NSDictionary *)dictionaryValue;

@end

NS_ASSUME_NONNULL_END
