#import <Foundation/Foundation.h>

extern int gButtonsB;
void (*FixtureHandlerFor(int kind))(int);

@interface ButtonStyle : NSObject
- (void)reset;
- (void)fixture_dispatch:(SEL)selector onTarget:(id)target;
@end
