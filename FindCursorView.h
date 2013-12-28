//
//  FindCursorView.h
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import <Cocoa/Cocoa.h>

@interface FindCursorView : NSView {
    NSPoint cursor;
}

@property (nonatomic, assign) NSPoint cursor;

@end
