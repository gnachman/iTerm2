#import <Foundation/Foundation.h>

@protocol MultiNaming
@property (nonatomic, copy) NSString *label;
@end

@interface Multi : NSObject <MultiNaming>
@property (nonatomic, strong) NSString *autoProp;
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic, assign) BOOL gone;
@property (nonatomic, strong) NSArray *items;
@end

@interface Multi (Extra)
- (void)extraWork;
@end
