//
//  iTermLegacyView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/5/21.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermLegacyView;

@protocol iTermLegacyViewDelegate<NSObject>
- (void)legacyView:(iTermLegacyView *)legacyView drawRect:(NSRect)dirtyRect;
@end

@interface iTermLegacyView : NSView
@property (nonatomic, weak) id<iTermLegacyViewDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
