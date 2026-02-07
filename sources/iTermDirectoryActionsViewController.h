//
//  iTermDirectoryActionsViewController.h
//  iTerm2SharedARC
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermDirectoryActionsViewController;

@protocol iTermDirectoryActionsDelegate <NSObject>
- (void)directoryActionsDidSelectCopyPath;
- (void)directoryActionsDidSelectCopyBasename;
- (void)directoryActionsDidSelectOpenInFinder;
- (void)directoryActionsDidSelectOpenInNewWindow;
- (void)directoryActionsDidSelectOpenInNewTab;
@end

@interface iTermDirectoryActionsViewController : NSViewController

@property (nonatomic, weak) id<iTermDirectoryActionsDelegate> delegate;
@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, strong) NSFont *font;

- (instancetype)initWithDirectoryPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
