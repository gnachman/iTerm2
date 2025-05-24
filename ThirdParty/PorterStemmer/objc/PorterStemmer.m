#import <Foundation/Foundation.h>
#import "PorterStemmer/objc/PorterStemmer.h"

#import "porter.c"

#define MAX_STEMMER_STRING_LEN	256

@implementation PorterStemmer

+ (NSString*)stemFromString:(NSString*)input
{
    struct stemmer stemmer;
	char stemBuffer[MAX_STEMMER_STRING_LEN];

	strncpy(stemBuffer, [input cStringUsingEncoding:NSUTF8StringEncoding],
			MAX_STEMMER_STRING_LEN - 1);

	int i = strlen(stemBuffer);
	stemBuffer[stem(&stemmer, stemBuffer, i - 1) + 1] = '\0';

	NSString* stem = [NSString stringWithCString:stemBuffer encoding:NSUTF8StringEncoding];
    return stem;
}

@end

@implementation NSString(PorterStemmer)
- (NSString*)stem
{
	return [PorterStemmer stemFromString:self];
}
@end
