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

#ifdef    __OBJC__
#import <Foundation/NSArray.h>
#import <Foundation/NSError.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#endif // __OBJC__

#include <limits.h>
#include <stdint.h>
#include <sys/types.h>
#include <TargetConditionals.h>
#include <AvailabilityMacros.h>

#ifdef __cplusplus
extern "C" {
#endif
  
#ifndef   REGEXKITLITE_VERSION_DEFINED
#define   REGEXKITLITE_VERSION_DEFINED

#define _RKL__STRINGIFY(b)       #b
#define _RKL_STRINGIFY(a)        _RKL__STRINGIFY(a)
#define _RKL_JOIN_VERSION(a,b)   _RKL_STRINGIFY(a##.##b)
#define _RKL_VERSION_STRING(a,b) _RKL_JOIN_VERSION(a,b)

#define REGEXKITLITE_VERSION_MAJOR 4
#define REGEXKITLITE_VERSION_MINOR 0

#define REGEXKITLITE_VERSION_CSTRING   _RKL_VERSION_STRING(REGEXKITLITE_VERSION_MAJOR, REGEXKITLITE_VERSION_MINOR)
#define REGEXKITLITE_VERSION_NSSTRING  @REGEXKITLITE_VERSION_CSTRING

#endif // REGEXKITLITE_VERSION_DEFINED

#if !defined(RKL_BLOCKS) && defined(NS_BLOCKS_AVAILABLE) && (NS_BLOCKS_AVAILABLE == 1)
#define RKL_BLOCKS 1
#endif
  
#if       defined(RKL_BLOCKS) && (RKL_BLOCKS == 1)
#define _RKL_BLOCKS_ENABLED 1
#endif // defined(RKL_BLOCKS) && (RKL_BLOCKS == 1)

#if       defined(_RKL_BLOCKS_ENABLED) && !defined(__BLOCKS__)
#warning RegexKitLite support for Blocks is enabled, but __BLOCKS__ is not defined.  This compiler may not support Blocks, in which case the behavior is undefined.  This will probably cause numerous compiler errors.
#endif // defined(_RKL_BLOCKS_ENABLED) && !defined(__BLOCKS__)

// For Mac OS X < 10.5.
#ifndef   NSINTEGER_DEFINED
#define   NSINTEGER_DEFINED
#if       defined(__LP64__) || defined(NS_BUILD_32_LIKE_64)
typedef long           NSInteger;
typedef unsigned long  NSUInteger;
#define NSIntegerMin   LONG_MIN
#define NSIntegerMax   LONG_MAX
#define NSUIntegerMax  ULONG_MAX
#else  // defined(__LP64__) || defined(NS_BUILD_32_LIKE_64)
typedef int            NSInteger;
typedef unsigned int   NSUInteger;
#define NSIntegerMin   INT_MIN
#define NSIntegerMax   INT_MAX
#define NSUIntegerMax  UINT_MAX
#endif // defined(__LP64__) || defined(NS_BUILD_32_LIKE_64)
#endif // NSINTEGER_DEFINED

#ifndef   RKLREGEXOPTIONS_DEFINED
#define   RKLREGEXOPTIONS_DEFINED

// These must be identical to their ICU regex counterparts. See http://www.icu-project.org/userguide/regexp.html
enum {
  RKLNoOptions             = 0,
  RKLCaseless              = 2,
  RKLComments              = 4,
  RKLDotAll                = 32,
  RKLMultiline             = 8,
  RKLUnicodeWordBoundaries = 256
};
typedef uint32_t RKLRegexOptions; // This must be identical to the ICU 'flags' argument type.

#endif // RKLREGEXOPTIONS_DEFINED

#ifndef   RKLREGEXENUMERATIONOPTIONS_DEFINED
#define   RKLREGEXENUMERATIONOPTIONS_DEFINED

enum {
  RKLRegexEnumerationNoOptions                               = 0UL,
  RKLRegexEnumerationCapturedStringsNotRequired              = 1UL << 9,
  RKLRegexEnumerationReleaseStringReturnedByReplacementBlock = 1UL << 10,
  RKLRegexEnumerationFastCapturedStringsXXX                  = 1UL << 11,
};
typedef NSUInteger RKLRegexEnumerationOptions;
  
#endif // RKLREGEXENUMERATIONOPTIONS_DEFINED

#ifndef _REGEXKITLITE_H_
#define _REGEXKITLITE_H_

#if defined(__GNUC__) && (__GNUC__ >= 4) && defined(__APPLE_CC__) && (__APPLE_CC__ >= 5465)
#define RKL_DEPRECATED_ATTRIBUTE __attribute__((deprecated))
#else
#define RKL_DEPRECATED_ATTRIBUTE
#endif

#if       defined(NS_REQUIRES_NIL_TERMINATION)
#define RKL_REQUIRES_NIL_TERMINATION NS_REQUIRES_NIL_TERMINATION
#else  // defined(NS_REQUIRES_NIL_TERMINATION)
#define RKL_REQUIRES_NIL_TERMINATION
#endif // defined(NS_REQUIRES_NIL_TERMINATION)
  
// This requires a few levels of rewriting to get the desired results.
#define _RKL_CONCAT_2(c,d) c ## d
#define _RKL_CONCAT(a,b) _RKL_CONCAT_2(a,b)
  
#ifdef    RKL_PREPEND_TO_METHODS
#define RKL_METHOD_PREPEND(x) _RKL_CONCAT(RKL_PREPEND_TO_METHODS, x)
#else  // RKL_PREPEND_TO_METHODS
#define RKL_METHOD_PREPEND(x) x
#endif // RKL_PREPEND_TO_METHODS
  
// If it looks like low memory notifications might be available, add code to register and respond to them.
// This is (should be) harmless if it turns out that this isn't the case, since the notification that we register for,
// UIApplicationDidReceiveMemoryWarningNotification, is dynamically looked up via dlsym().
#if ((defined(TARGET_OS_EMBEDDED) && (TARGET_OS_EMBEDDED != 0)) || (defined(TARGET_OS_IPHONE) && (TARGET_OS_IPHONE != 0))) && (!defined(RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS) || (RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS != 0))
#define RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS 1
#endif

#ifdef __OBJC__

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

// Although these are marked as deprecated, a bug in GCC prevents a warning from being issues for + class methods.  Filed bug with Apple, #6736857.
+ (NSInteger)RKL_METHOD_PREPEND(captureCountForRegex):(NSString *)regex RKL_DEPRECATED_ATTRIBUTE;
+ (NSInteger)RKL_METHOD_PREPEND(captureCountForRegex):(NSString *)regex options:(RKLRegexOptions)options error:(NSError **)error RKL_DEPRECATED_ATTRIBUTE;

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

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex withKeysAndCaptures:(id)firstKey, ... RKL_REQUIRES_NIL_TERMINATION;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex range:(NSRange)range withKeysAndCaptures:(id)firstKey, ... RKL_REQUIRES_NIL_TERMINATION;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeysAndCaptures:(id)firstKey, ... RKL_REQUIRES_NIL_TERMINATION;
- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withFirstKey:(id)firstKey arguments:(va_list)varArgsList;

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeys:(id *)keys forCaptures:(int *)captures count:(NSUInteger)count;

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex withKeysAndCaptures:(id)firstKey, ... RKL_REQUIRES_NIL_TERMINATION;
- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex range:(NSRange)range withKeysAndCaptures:(id)firstKey, ... RKL_REQUIRES_NIL_TERMINATION;
- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeysAndCaptures:(id)firstKey, ... RKL_REQUIRES_NIL_TERMINATION;
- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withFirstKey:(id)firstKey arguments:(va_list)varArgsList;

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeys:(id *)keys forCaptures:(int *)captures count:(NSUInteger)count;

#ifdef    _RKL_BLOCKS_ENABLED

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsMatchedByRegex):(NSString *)regex usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (BOOL)RKL_METHOD_PREPEND(enumerateStringsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsSeparatedByRegex):(NSString *)regex usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (BOOL)RKL_METHOD_PREPEND(enumerateStringsSeparatedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

#endif // _RKL_BLOCKS_ENABLED

@end

@interface NSMutableString (RegexKitLiteAdditions)

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement;
- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement range:(NSRange)searchRange;
- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement options:(RKLRegexOptions)options range:(NSRange)searchRange error:(NSError **)error;

  //// >= 4.0

#ifdef    _RKL_BLOCKS_ENABLED

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;
- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block;

#endif // _RKL_BLOCKS_ENABLED

@end

#endif // __OBJC__

#endif // _REGEXKITLITE_H_

#ifdef __cplusplus
}  // extern "C"
#endif
