#import <Foundation/Foundation.h>

@interface PorterStemmer : NSObject
{
}

+ (NSString*)stemFromString:(NSString*)input;

@end

@interface NSString(PorterStemmer)
- (NSString*)stem;
@end
