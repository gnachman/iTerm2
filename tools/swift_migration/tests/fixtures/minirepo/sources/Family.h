#import <Foundation/Foundation.h>

typedef void (^FamilyBlock)(void);

@interface Parent : NSObject
@property (nonatomic, strong) NSString *common;
@property (nonatomic, readonly) NSInteger depth;
@end

@interface Child : Parent
@property (nonatomic, strong) NSString *common;
@property (nonatomic, readonly) NSString *computed;
@property (nonatomic, weak) id owner;
@property (nonatomic, strong) NSString *shout;
@property (nonatomic, readonly) NSInteger depth;
@end
