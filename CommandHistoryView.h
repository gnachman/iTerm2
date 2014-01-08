//
//  CommandHistoryView.h
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import <Cocoa/Cocoa.h>

@protocol CommandHistoryViewDelegate <NSObject>

- (void)commandHistoryViewDidSelectCommand:(NSString *)command;

@end

@interface CommandHistoryView : NSView

@property(nonatomic, retain) NSArray *commands;
@property(nonatomic, assign) id<CommandHistoryViewDelegate> delegate;

- (NSSize)desiredSize;

- (BOOL)wantsKeyDown:(NSEvent *)event;

@end
