//
//  iTermDisclosableView.h
//  iTerm2
//
//  Created by George Nachman on 11/29/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermDisclosableView : NSView

@property (nonatomic, copy) void (^requestLayout)(void);
@property (nonatomic, readonly) NSTextView *textView;

- (instancetype)initWithFrame:(NSRect)frameRect prompt:(NSString *)prompt message:(NSString *)message NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)decoder NS_UNAVAILABLE;

@end

@interface iTermScrollingDisclosableView : iTermDisclosableView
- (instancetype)initWithFrame:(NSRect)frameRect prompt:(NSString *)prompt message:(NSString *)message maximumHeight:(CGFloat)maximumHeight NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect prompt:(NSString *)prompt message:(NSString *)message NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)decoder NS_UNAVAILABLE;
@end

// Hides auto layout from NSAlert.
@interface iTermAccessoryViewUnfucker: NSView
@property (nonatomic, readonly) NSView *contentView;

- (instancetype)initWithView:(NSView *)contentView NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)layout;

@end

