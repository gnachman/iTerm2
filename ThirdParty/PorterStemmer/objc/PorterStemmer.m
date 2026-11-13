#import <Foundation/Foundation.h>
#import "PorterStemmer/objc/PorterStemmer.h"

#import "porter.c"

#define MAX_STEMMER_STRING_LEN	256

@implementation PorterStemmer

+ (NSString*)stemFromString:(NSString*)input
{
    struct stemmer stemmer;
	char stemBuffer[MAX_STEMMER_STRING_LEN];

    // cStringUsingEncoding: returns NULL when the string can't be encoded (e.g., a lone
    // surrogate). A word too long for the buffer is left alone rather than truncated, since
    // truncating could split a multibyte character and isn't a meaningful stem anyway.
    const char *cString = [input cStringUsingEncoding:NSUTF8StringEncoding];
    if (!cString) {
        return input;
    }
    const size_t length = strlen(cString);
    if (length >= MAX_STEMMER_STRING_LEN) {
        return input;
    }
    memcpy(stemBuffer, cString, length + 1);

	stemBuffer[stem(&stemmer, stemBuffer, (int)length - 1) + 1] = '\0';

	NSString* stem = [NSString stringWithCString:stemBuffer encoding:NSUTF8StringEncoding];
    return stem ?: input;
}

@end

@implementation NSString(PorterStemmer)
- (NSString*)stem
{
	return [PorterStemmer stemFromString:self];
}
@end
