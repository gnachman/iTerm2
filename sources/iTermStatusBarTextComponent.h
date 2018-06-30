//
//  iTermStatusBarTextComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Foundation/Foundation.h>
#import "iTermStatusBarComponent.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

@interface iTermStatusBarBaseComponent : NSObject<iTermStatusBarComponent>

@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSDictionary<iTermStatusBarComponentConfigurationKey, id> *configuration;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// A base class for components that show text.
// This class only knows how to show static text. Subclasses may choose to configure it by overriding
// stringValue, attributedStringValue, statusBarComponentVariableDependencies,
// statusBarComponentUpdateCadence, and statusBarComponentUpdate.
@interface iTermStatusBarTextComponent : iTermStatusBarBaseComponent

@property (nonatomic, readonly, nullable) NSString *stringValue;
@property (nonatomic, readonly, nullable) NSAttributedString *attributedStringValue;
@property (nonatomic, readonly) NSTextField *textField;

@end

@interface iTermStatusBarFixedSpacerComponent : iTermStatusBarBaseComponent
@end

@interface iTermStatusBarSpringComponent : iTermStatusBarBaseComponent
@end

NS_ASSUME_NONNULL_END
