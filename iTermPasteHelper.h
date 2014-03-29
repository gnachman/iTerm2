//
//  iTermPasteHelper.h
//  iTerm
//
//  Created by George Nachman on 3/29/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PasteEvent.h"

@protocol iTermPasteHelperDelegate <NSObject>

- (void)pasteHelperWriteData:(NSData *)data;

// Handle a key-down event that was previously enequeued.
- (void)pasteHelperKeyDown:(NSEvent *)event;

// Indicates if pastes should be bracketed with a special escape sequence.
- (BOOL)pasteHelperShouldBracket;

// Encoding to use for converting strings to byte arrays.
- (NSStringEncoding)pasteHelperEncoding;

// View in which to show the paste indicator.
- (NSView *)pasteHelperViewForIndicator;

@end

@interface iTermPasteHelper : NSObject

@property(nonatomic, assign) id<iTermPasteHelperDelegate> delegate;
@property(nonatomic, readonly) BOOL isPasting;

// Queue up a string to paste. If the queue is empty, it will begin pasting immediately.
- (void)pasteString:(NSString *)theString flags:(PTYSessionPasteFlags)flags;

// Save an event to process after pasting is done.
- (void)enqueueEvent:(NSEvent *)event;

// Remove all queued events and pending pastes, and hide the paste indicator if shown.
- (void)abort;

@end
