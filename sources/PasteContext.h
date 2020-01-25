//
//  PasteContext.h
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import <Foundation/Foundation.h>

@class PasteEvent;

@interface PasteContext : NSObject

@property(nonatomic, assign) int bytesPerCall;
@property(nonatomic, assign) float delayBetweenCalls;
@property(nonatomic, assign) BOOL blockAtNewline;
@property(nonatomic, assign) BOOL isBlocked;
@property(nonatomic, assign) BOOL isUpload;
@property(nonatomic, copy) void (^progress)(NSInteger);
@property(nonatomic, assign) NSInteger bytesWritten;
@property(nonatomic, readonly) PasteEvent *pasteEvent;

- (instancetype)initWithPasteEvent:(PasteEvent *)pasteEvent;

- (void)updateValues;

@end
