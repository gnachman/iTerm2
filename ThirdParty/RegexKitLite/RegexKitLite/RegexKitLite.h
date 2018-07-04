//
//  RegexKitLite.h
//  http://regexkit.sourceforge.net/
//  Licensed under the terms of the BSD License, as specified below.
//

/*
 Copyright (c) 2008-2010, John Engelhart
 
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 * Neither the name of the Zang Industries nor the names of its
 contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#import <Foundation/NSArray.h>
#import <Foundation/NSError.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>

#include <limits.h>
#include <stdint.h>
#include <sys/types.h>
#include <TargetConditionals.h>
#include <AvailabilityMacros.h>


#ifdef __cplusplus
extern "C" {
#endif

	
//! Project version number for RegexKitLite.
FOUNDATION_EXPORT double RegexKitLiteVersionNumber;

//! Project version string for RegexKitLite.
FOUNDATION_EXPORT const unsigned char RegexKitLiteVersionString[];


#ifndef REGEX_KIT_LITE
#define REGEX_KIT_LITE

#define REGEXKITLITE_VERSION_NUMBER_MAJOR 4
#define REGEXKITLITE_VERSION_NUMBER_MINOR 1

#define REGEXKITLITE_VERSION_NUMBER_STRING @"4.1"


// These must be identical to their ICU regex counterparts. See http://www.icu-project.org/userguide/regexp.html
// This must be identical to the ICU 'flags' argument type.
typedef NS_ENUM(uint32_t, RKLRegexOptions) {
	RKLNoOptions             = 0,
	RKLCaseless              = 2,
	RKLComments              = 4,
	RKLDotAll                = 32,
	RKLMultiline             = 8,
	RKLUnicodeWordBoundaries = 256
};

typedef NS_ENUM(NSUInteger, RKLRegexEnumerationOptions) {
	RKLRegexEnumerationNoOptions                               = 0UL,
	RKLRegexEnumerationCapturedStringsNotRequired              = 1UL << 9,
	RKLRegexEnumerationReleaseStringReturnedByReplacementBlock = 1UL << 10,
	RKLRegexEnumerationFastCapturedStringsXXX                  = 1UL << 11,
};


// This requires a few levels of rewriting to get the desired results.
#define _RKL_CONCAT_2(c,d) c ## d
#define _RKL_CONCAT(a,b) _RKL_CONCAT_2(a,b)

// Mechanism for appending a custom prefix to public methods
#ifdef    RKL_PREPEND_TO_METHODS
#define RKL_METHOD_PREPEND(x) _RKL_CONCAT(RKL_PREPEND_TO_METHODS, x)
#else  // RKL_PREPEND_TO_METHODS
#define RKL_METHOD_PREPEND(x) x
#endif // RKL_PREPEND_TO_METHODS


// NSException exception name.
extern NSString * const RKLICURegexException;

// NSError error domains and user info keys.
extern NSString * const RKLICURegexErrorDomain;

extern NSString * const RKLICURegexEnumerationOptionsErrorKey;
extern NSString * const RKLICURegexErrorCodeErrorKey;
extern NSString * const RKLICURegexErrorNameErrorKey;
extern NSString * const RKLICURegexLineErrorKey;
extern NSString * const RKLICURegexOffsetErrorKey;
extern NSString * const RKLICURegexPreContextErrorKey;
extern NSString * const RKLICURegexPostContextErrorKey;
extern NSString * const RKLICURegexRegexErrorKey;
extern NSString * const RKLICURegexRegexOptionsErrorKey;
extern NSString * const RKLICURegexReplacedCountErrorKey;
extern NSString * const RKLICURegexReplacedStringErrorKey;
extern NSString * const RKLICURegexReplacementStringErrorKey;
extern NSString * const RKLICURegexSubjectRangeErrorKey;
extern NSString * const RKLICURegexSubjectStringErrorKey;

@interface NSString (RegexKitLiteAdditions)

+ (void)RKL_METHOD_PREPEND(clearStringCache);

- (NSArray *)RKL_METHOD_PREPEND(componentsSeparatedByRegex):(NSString *)regex;
- (NSArray *)RKL_METHOD_PREPEND(componentsSeparatedByRegex):(NSString *)regex range:(NSRange)range;
- (NSArray *)RKL_METHOD_PREPEND(componentsSeparatedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error;

- (BOOL)RKL_METHOD_PREPEND(isMatchedByRegex):(NSString *)regex;
- (BOOL)RKL_METHOD_PREPEND(isMatchedByRegex):(NSString *)regex inRange:(NSRange)range;
- (BOOL)RKL_METHOD_PREPEND(isMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error;

- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex;
- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex capture:(NSInteger)capture;
- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex inRange:(NSRange)range;
- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range capture:(NSInteger)capture error:(NSError **)error;

- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex;
- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex capture:(NSInteger)capture;
- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex inRange:(NSRange)range;
- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range capture:(NSInteger)capture error:(NSError **)error;

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement;
- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement range:(NSRange)searchRange;
- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement options:(RKLRegexOptions)options range:(NSRange)searchRange error:(NSError **)error;

//// >= 3.0

- (NSInteger)RKL_METHOD_PREPEND(captureCount);
- (NSInteger)RKL_METHOD_PREPEND(captureCountWithOptions):(RKLRegexOptions)options error:(NSError **)error;

- (BOOL)RKL_METHOD_PREPEND(isRegexValid);
- (BOOL)RKL_METHOD_PREPEND(isRegexValidWithOptions):(RKLRegexOptions)options error:(NSError **)error;

- (void)RKL_METHOD_PREPEND(flushCachedRegexData);

- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex;
- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex capture:(NSInteger)capture;
- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex range:(NSRange)range;
- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range capture:(NSInteger)capture error:(NSError **)error;


- (NSArray *)RKL_METHOD_PREPEND(captureComponentsMatchedByRegex):(NSString *)regex;
- (NSArray *)RKL_METHOD_PREPEND(captureComponentsMatchedByRegex):(NSString *)regex range:(NSRange)range;
- (NSArray *)RKL_METHOD_PREPEND(captureComponentsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error;

- (NSArray *)RKL_METHOD_PREPEND(arrayOfCaptureComponentsMatchedByRegex):(NSString *)regex;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfCaptureComponentsMatchedByRegex):(NSString *)regex range:(NSRange)range;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfCaptureComponentsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error;

//// >= 4.0

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex withKeysAndCaptures:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex range:(NSRange)range withKeysAndCaptures:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeysAndCaptures:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withFirstKey:(id)firstKey arguments:(va_list)varArgsList;

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeys:(id *)keys forCaptures:(int *)captures count:(NSUInteger)count;

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex withKeysAndCaptures:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex range:(NSRange)range withKeysAndCaptures:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeysAndCaptures:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withFirstKey:(id)firstKey arguments:(va_list)varArgsList;

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeys:(id *)keys forCaptures:(int *)captures count:(NSUInteger)count;

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsMatchedByRegex):(NSString *)regex usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (BOOL)RKL_METHOD_PREPEND(enumerateStringsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsSeparatedByRegex):(NSString *)regex usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (BOOL)RKL_METHOD_PREPEND(enumerateStringsSeparatedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;


@end


@interface NSMutableString (RegexKitLiteAdditions)

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement;
- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement range:(NSRange)searchRange;
- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement options:(RKLRegexOptions)options range:(NSRange)searchRange error:(NSError **)error;

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

@end

	
#endif // REGEX_KIT_LITE

	
#ifdef __cplusplus
}  // extern "C"
#endif
