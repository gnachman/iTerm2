//
//  iTermJobTreeViewController.h
//  iTerm2
//
//  Created by George Nachman on 1/18/19.
//

#import <Cocoa/Cocoa.h>

@protocol ProcessInfoProvider;

NS_ASSUME_NONNULL_BEGIN

@interface iTermJobTreeViewController : NSViewController
@property (nonatomic) pid_t pid;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic) BOOL animateChanges;
@property (nonatomic) id<ProcessInfoProvider> processInfoProvider;

- (instancetype)initWithProcessID:(pid_t)pid
              processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (void)setFont:(NSFont *)font;
- (void)sizeOutlineViewToFit;

@end

NS_ASSUME_NONNULL_END
