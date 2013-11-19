//
//  PTYNoteView.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>

@protocol PTYNoteViewDelegate <NSObject>
@end

@interface PTYNoteView : NSView {
    id<PTYNoteViewDelegate> delegate_;
}

@property(nonatomic, assign) id<PTYNoteViewDelegate> delegate;

@end
