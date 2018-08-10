//
//  PSMMinimalTabStyle.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMYosemiteTabStyle.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PSMMinimalTabStyleDelegate<NSObject>
- (NSColor *)minimalTabStyleBackgroundColor;
@end

@interface PSMMinimalTabStyle : PSMYosemiteTabStyle
@property (nonatomic, weak) id<PSMMinimalTabStyleDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
