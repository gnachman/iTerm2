//
//  PseudoTerminalRestorer.h
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// Top-level key for restorable window state when using the SQLite restorer.
extern NSString *const iTermWindowStateKeyGUID;

@interface PseudoTerminalState: NSObject
@property (nonatomic, readonly) NSDictionary *arrangement;
@property (nonatomic, readonly) NSCoder *coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (instancetype)initWithDictionary:(NSDictionary *)arrangement;
@end

@interface PseudoTerminalRestorer : NSObject<NSWindowRestoration>

@property(class, nonatomic) void (^postRestorationCompletionBlock)(void);

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler;

+ (BOOL)willOpenWindows;

// Block is run when all windows are restored. It may be run immediately.
+ (void)setRestorationCompletionBlock:(void(^)(void))completion;

+ (void)runQueuedBlocks;

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                pseudoTerminalState:(PseudoTerminalState *)state
                             system:(BOOL)system
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler;

// The db-backed restoration mechansim has completed and the post-restoration callback is now safe to run.
+ (void)externalRestorationDidComplete;

@end
