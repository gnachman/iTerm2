//
//  iTermStatusBarBaseComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import <Foundation/Foundation.h>
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarLayout.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

// Knob key taking a number.
extern NSString *const iTermStatusBarPriorityKey;
extern NSString *const iTermStatusBarMaximumWidthKey;
extern NSString *const iTermStatusBarMinimumWidthKey;

@interface iTermStatusBarBaseComponent : NSObject<iTermStatusBarComponent>

@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSDictionary<iTermStatusBarComponentConfigurationKey, id> *configuration;
@property (nonatomic, readonly) NSColor *statusBarBackgroundColor;
@property (nonatomic, readonly) NSColor *defaultTextColor;
@property (nonatomic, readonly) iTermStatusBarAdvancedConfiguration *advancedConfiguration;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<iTermStatusBarComponentKnob *> *)minMaxWidthKnobs;
// Clamp width to min/max knobs' values.
- (CGFloat)clampedWidth:(CGFloat)width;
+ (NSDictionary *)defaultMinMaxWidthKnobValues;

@end

@interface iTermStatusBarBuiltInComponentFactory : NSObject<iTermStatusBarComponentFactory>

- (instancetype)initWithClass:(Class)theClass;

@end

NS_ASSUME_NONNULL_END
