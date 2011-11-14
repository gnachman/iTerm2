//
//  RegexKitLite.m
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

#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSRunLoop.h>
#ifdef    __OBJC_GC__
#import <Foundation/NSGarbageCollector.h>
#define RKL_STRONG_REF __strong
#define RKL_GC_VOLATILE volatile
#else  // __OBJC_GC__
#define RKL_STRONG_REF
#define RKL_GC_VOLATILE
#endif // __OBJC_GC__

#if (defined(TARGET_OS_EMBEDDED) && (TARGET_OS_EMBEDDED != 0)) || (defined(TARGET_OS_IPHONE) && (TARGET_OS_IPHONE != 0)) || (defined(MAC_OS_X_VERSION_MIN_REQUIRED) && (MAC_OS_X_VERSION_MIN_REQUIRED >= 1050))
#include <objc/runtime.h>
#else
#include <objc/objc-runtime.h>
#endif

#include <libkern/OSAtomic.h>
#include <mach-o/loader.h>
#include <AvailabilityMacros.h>
#include <dlfcn.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>

#import "RegexKitLite.h"

// If the gcc flag -mmacosx-version-min is used with, for example, '=10.2', give a warning that the libicucore.dylib is only available on >= 10.3.
// If you are reading this comment because of this warning, this is to let you know that linking to /usr/lib/libicucore.dylib will cause your executable to fail on < 10.3.
// You will need to build your own version of the ICU library and link to that in order for RegexKitLite to work successfully on < 10.3.  This is not simple.

#if MAC_OS_X_VERSION_MIN_REQUIRED < 1030
#warning The ICU dynamic shared library, /usr/lib/libicucore.dylib, is only available on Mac OS X 10.3 and later.
#warning You will need to supply a version of the ICU library to use RegexKitLite on Mac OS X 10.2 and earlier.
#endif

////////////
#pragma mark Compile time tunables

#ifndef RKL_CACHE_SIZE
#define RKL_CACHE_SIZE (13UL)
#endif

#if       RKL_CACHE_SIZE < 1
#error RKL_CACHE_SIZE must be a non-negative number greater than 0.
#endif // RKL_CACHE_SIZE < 1

#ifndef RKL_FIXED_LENGTH
#define RKL_FIXED_LENGTH (2048UL)
#endif

#if       RKL_FIXED_LENGTH < 1
#error RKL_FIXED_LENGTH must be a non-negative number greater than 0.
#endif // RKL_FIXED_LENGTH < 1

#ifndef RKL_STACK_LIMIT
#define RKL_STACK_LIMIT (128UL * 1024UL)
#endif

#if       RKL_STACK_LIMIT < 0
#error RKL_STACK_LIMIT must be a non-negative number.
#endif // RKL_STACK_LIMIT < 0

#ifdef    RKL_APPEND_TO_ICU_FUNCTIONS
#define RKL_ICU_FUNCTION_APPEND(x) _RKL_CONCAT(x, RKL_APPEND_TO_ICU_FUNCTIONS)
#else  // RKL_APPEND_TO_ICU_FUNCTIONS
#define RKL_ICU_FUNCTION_APPEND(x) x
#endif // RKL_APPEND_TO_ICU_FUNCTIONS

#if       defined(RKL_DTRACE) && (RKL_DTRACE != 0)
#define _RKL_DTRACE_ENABLED 1
#endif // defined(RKL_DTRACE) && (RKL_DTRACE != 0)

// These are internal, non-public tunables.
#define _RKL_FIXED_LENGTH                ((NSUInteger)RKL_FIXED_LENGTH)
#define _RKL_STACK_LIMIT                 ((NSUInteger)RKL_STACK_LIMIT)
#define _RKL_SCRATCH_BUFFERS             (5UL)
#if       _RKL_SCRATCH_BUFFERS != 5
#error _RKL_SCRATCH_BUFFERS is not tunable, it must be set to 5.
#endif // _RKL_SCRATCH_BUFFERS != 5
#define _RKL_PREFETCH_SIZE               (64UL)
#define _RKL_DTRACE_REGEXUTF8_SIZE       (64UL)

// A LRU Cache Set holds 4 lines, and the LRU algorithm uses 4 bits per line.
// A LRU Cache Set has a type of RKLLRUCacheSet_t and is 16 bits wide (4 lines * 4 bits per line).
// RKLLRUCacheSet_t must be initialized to a value of 0x0137 in order to work correctly.
typedef uint16_t RKLLRUCacheSet_t;
#define _RKL_LRU_CACHE_SET_INIT          ((RKLLRUCacheSet_t)0x0137U)
#define _RKL_LRU_CACHE_SET_WAYS          (4UL)
#if       _RKL_LRU_CACHE_SET_WAYS != 4
#error _RKL_LRU_CACHE_SET_WAYS is not tunable, it must be set to 4.
#endif // _RKL_LRU_CACHE_SET_WAYS != 4

#define _RKL_REGEX_LRU_CACHE_SETS        ((NSUInteger)(RKL_CACHE_SIZE))
#define _RKL_REGEX_CACHE_LINES           ((NSUInteger)((NSUInteger)(_RKL_REGEX_LRU_CACHE_SETS) * (NSUInteger)(_RKL_LRU_CACHE_SET_WAYS)))

// Regex String Lookaside Cache parameters.
#define _RKL_REGEX_LOOKASIDE_CACHE_BITS   (6UL)
#if       _RKL_REGEX_LOOKASIDE_CACHE_BITS < 0
#error _RKL_REGEX_LOOKASIDE_CACHE_BITS must be a non-negative number and is not intended to be user tunable.
#endif // _RKL_REGEX_LOOKASIDE_CACHE_BITS < 0
#define _RKL_REGEX_LOOKASIDE_CACHE_SIZE   (1LU << _RKL_REGEX_LOOKASIDE_CACHE_BITS)
#define _RKL_REGEX_LOOKASIDE_CACHE_MASK  ((1LU << _RKL_REGEX_LOOKASIDE_CACHE_BITS) - 1LU)
// RKLLookasideCache_t should be large enough to to hold the maximum number of cached regexes, or (RKL_CACHE_SIZE * _RKL_LRU_CACHE_SET_WAYS).
#if       (RKL_CACHE_SIZE * _RKL_LRU_CACHE_SET_WAYS) <= (1 << 8)
typedef uint8_t RKLLookasideCache_t;
#elif     (RKL_CACHE_SIZE * _RKL_LRU_CACHE_SET_WAYS) <= (1 << 16)
typedef uint16_t RKLLookasideCache_t;
#else  // (RKL_CACHE_SIZE * _RKL_LRU_CACHE_SET_WAYS)  > (1 << 16)
typedef uint32_t RKLLookasideCache_t;
#endif // (RKL_CACHE_SIZE * _RKL_LRU_CACHE_SET_WAYS)

//////////////
#pragma mark -
#pragma mark GCC / Compiler macros

#if       defined (__GNUC__) && (__GNUC__ >= 4)
#define RKL_ATTRIBUTES(attr, ...)        __attribute__((attr, ##__VA_ARGS__))
#define RKL_EXPECTED(cond, expect)       __builtin_expect((long)(cond), (expect))
#define RKL_PREFETCH(ptr)                __builtin_prefetch(ptr)
#define RKL_PREFETCH_UNICHAR(ptr, off)   { const char *p = ((const char *)(ptr)) + ((off) * sizeof(UniChar)) + _RKL_PREFETCH_SIZE; RKL_PREFETCH(p); RKL_PREFETCH(p + _RKL_PREFETCH_SIZE); }
#define RKL_HAVE_CLEANUP
#define RKL_CLEANUP(func)                RKL_ATTRIBUTES(cleanup(func))
#else  // defined (__GNUC__) && (__GNUC__ >= 4) 
#define RKL_ATTRIBUTES(attr, ...)
#define RKL_EXPECTED(cond, expect)       (cond)
#define RKL_PREFETCH(ptr)
#define RKL_PREFETCH_UNICHAR(ptr, off)
#define RKL_CLEANUP(func)
#endif // defined (__GNUC__) && (__GNUC__ >= 4) 

#define RKL_STATIC_INLINE                         static __inline__ RKL_ATTRIBUTES(always_inline)
#define RKL_ALIGNED(arg)                                            RKL_ATTRIBUTES(aligned(arg))
#define RKL_UNUSED_ARG                                              RKL_ATTRIBUTES(unused)
#define RKL_WARN_UNUSED                                             RKL_ATTRIBUTES(warn_unused_result)
#define RKL_WARN_UNUSED_CONST                                       RKL_ATTRIBUTES(warn_unused_result, const)
#define RKL_WARN_UNUSED_PURE                                        RKL_ATTRIBUTES(warn_unused_result, pure)
#define RKL_WARN_UNUSED_SENTINEL                                    RKL_ATTRIBUTES(warn_unused_result, sentinel)
#define RKL_NONNULL_ARGS(arg, ...)                                  RKL_ATTRIBUTES(nonnull(arg, ##__VA_ARGS__))
#define RKL_WARN_UNUSED_NONNULL_ARGS(arg, ...)                      RKL_ATTRIBUTES(warn_unused_result, nonnull(arg, ##__VA_ARGS__))
#define RKL_WARN_UNUSED_CONST_NONNULL_ARGS(arg, ...)                RKL_ATTRIBUTES(warn_unused_result, const, nonnull(arg, ##__VA_ARGS__))
#define RKL_WARN_UNUSED_PURE_NONNULL_ARGS(arg, ...)                 RKL_ATTRIBUTES(warn_unused_result, pure, nonnull(arg, ##__VA_ARGS__))

#if       defined (__GNUC__) && (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)
#define RKL_ALLOC_SIZE_NON_NULL_ARGS_WARN_UNUSED(as, nn, ...) RKL_ATTRIBUTES(warn_unused_result, nonnull(nn, ##__VA_ARGS__), alloc_size(as))
#else  // defined (__GNUC__) && (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)
#define RKL_ALLOC_SIZE_NON_NULL_ARGS_WARN_UNUSED(as, nn, ...) RKL_ATTRIBUTES(warn_unused_result, nonnull(nn, ##__VA_ARGS__))
#endif // defined (__GNUC__) && (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)

#ifdef    _RKL_DTRACE_ENABLED
#define RKL_UNUSED_DTRACE_ARG
#else  // _RKL_DTRACE_ENABLED
#define RKL_UNUSED_DTRACE_ARG RKL_ATTRIBUTES(unused)
#endif // _RKL_DTRACE_ENABLED

////////////
#pragma mark -
#pragma mark Assertion macros

// These macros are nearly identical to their NSCParameterAssert siblings.
// This is required because nearly everything is done while rkl_cacheSpinLock is locked.
// We need to safely unlock before throwing any of these exceptions.
// @try {} @finally {} significantly slows things down so it's not used.

#define RKLCHardAbortAssert(c) do { int _c=(c); if(RKL_EXPECTED(!_c, 0L)) { NSLog(@"%@:%ld: Invalid parameter not satisfying: %s\n", [NSString stringWithUTF8String:__FILE__], (long)__LINE__, #c); abort(); } } while(0)
#define RKLCAssertDictionary(d, ...) rkl_makeAssertDictionary(__PRETTY_FUNCTION__, __FILE__, __LINE__, (d), ##__VA_ARGS__)
#define RKLCDelayedHardAssert(c, e, g) do { id *_e=(e); int _c=(c); if(RKL_EXPECTED(_e == NULL, 0L) || RKL_EXPECTED(*_e != NULL, 0L)) { goto g; } if(RKL_EXPECTED(!_c, 0L)) { *_e = RKLCAssertDictionary(@"Invalid parameter not satisfying: %s", #c); goto g; } } while(0)

#ifdef    NS_BLOCK_ASSERTIONS
#define RKLCAbortAssert(c)
#define RKLCDelayedAssert(c, e, g)
#define RKL_UNUSED_ASSERTION_ARG RKL_ATTRIBUTES(unused)
#else  // NS_BLOCK_ASSERTIONS
#define RKLCAbortAssert(c) RKLCHardAbortAssert(c)
#define RKLCDelayedAssert(c, e, g) RKLCDelayedHardAssert(c, e, g)
#define RKL_UNUSED_ASSERTION_ARG
#endif // NS_BLOCK_ASSERTIONS

#define RKL_EXCEPTION(e, f, ...)       [NSException exceptionWithName:(e) reason:rkl_stringFromClassAndMethod((self), (_cmd), (f), ##__VA_ARGS__) userInfo:NULL]
#define RKL_RAISE_EXCEPTION(e, f, ...) [RKL_EXCEPTION(e, f, ##__VA_ARGS__) raise]

////////////
#pragma mark -
#pragma mark Utility functions and macros

RKL_STATIC_INLINE BOOL NSRangeInsideRange(NSRange cin, NSRange win) RKL_WARN_UNUSED;
RKL_STATIC_INLINE BOOL NSRangeInsideRange(NSRange cin, NSRange win) { return((((cin.location - win.location) <= win.length) && ((NSMaxRange(cin) - win.location) <= win.length)) ? YES : NO); }

#define NSMakeRange(loc, len) ((NSRange){.location=(NSUInteger)(loc),      .length=(NSUInteger)(len)})
#define CFMakeRange(loc, len) ((CFRange){.location=   (CFIndex)(loc),      .length=   (CFIndex)(len)})
#define NSNotFoundRange       ((NSRange){.location=(NSUInteger)NSNotFound, .length=              0UL})
#define NSMaxiumRange         ((NSRange){.location=                   0UL, .length=    NSUIntegerMax})
// These values are used to help tickle improper usage.
#define RKLIllegalRange       ((NSRange){.location=          NSIntegerMax, .length=     NSIntegerMax})
#define RKLIllegalPointer     ((void * RKL_GC_VOLATILE)0xBAD0C0DE)

////////////
#pragma mark -
#pragma mark Exported NSString symbols for exception names, error domains, error keys, etc

NSString * const RKLICURegexException                  = @"RKLICURegexException";

NSString * const RKLICURegexErrorDomain                = @"RKLICURegexErrorDomain";

NSString * const RKLICURegexEnumerationOptionsErrorKey = @"RKLICURegexEnumerationOptions";
NSString * const RKLICURegexErrorCodeErrorKey          = @"RKLICURegexErrorCode";
NSString * const RKLICURegexErrorNameErrorKey          = @"RKLICURegexErrorName";
NSString * const RKLICURegexLineErrorKey               = @"RKLICURegexLine";
NSString * const RKLICURegexOffsetErrorKey             = @"RKLICURegexOffset";
NSString * const RKLICURegexPreContextErrorKey         = @"RKLICURegexPreContext";
NSString * const RKLICURegexPostContextErrorKey        = @"RKLICURegexPostContext";
NSString * const RKLICURegexRegexErrorKey              = @"RKLICURegexRegex";
NSString * const RKLICURegexRegexOptionsErrorKey       = @"RKLICURegexRegexOptions";
NSString * const RKLICURegexReplacedCountErrorKey      = @"RKLICURegexReplacedCount";
NSString * const RKLICURegexReplacedStringErrorKey     = @"RKLICURegexReplacedString";
NSString * const RKLICURegexReplacementStringErrorKey  = @"RKLICURegexReplacementString";
NSString * const RKLICURegexSubjectRangeErrorKey       = @"RKLICURegexSubjectRange";
NSString * const RKLICURegexSubjectStringErrorKey      = @"RKLICURegexSubjectString";

// Used internally by rkl_userInfoDictionary to specify which arguments should be set in the NSError userInfo dictionary.
enum {
  RKLUserInfoNone                    = 0UL,
  RKLUserInfoSubjectRange            = 1UL << 0,
  RKLUserInfoReplacedCount           = 1UL << 1,
  RKLUserInfoRegexEnumerationOptions = 1UL << 2,
};
typedef NSUInteger RKLUserInfoOptions;

////////////
#pragma mark -
#pragma mark Type / struct definitions

// In general, the ICU bits and pieces here must exactly match the definition in the ICU sources.

#define U_STRING_NOT_TERMINATED_WARNING -124
#define U_ZERO_ERROR                       0
#define U_INDEX_OUTOFBOUNDS_ERROR          8
#define U_BUFFER_OVERFLOW_ERROR           15
#define U_PARSE_CONTEXT_LEN               16

typedef struct uregex uregex; // Opaque ICU regex type.

typedef struct UParseError { // This must be exactly the same as the 'real' ICU declaration.
  int32_t line;
  int32_t offset;
  UniChar preContext[U_PARSE_CONTEXT_LEN];
  UniChar postContext[U_PARSE_CONTEXT_LEN];
} UParseError;

// For use with GCC's cleanup() __attribute__.
enum {
  RKLLockedCacheSpinLock   = 1UL << 0,
  RKLUnlockedCacheSpinLock = 1UL << 1,
};

enum {
  RKLSplitOp                         = 1UL,
  RKLReplaceOp                       = 2UL,
  RKLRangeOp                         = 3UL,
  RKLArrayOfStringsOp                = 4UL,
  RKLArrayOfCapturesOp               = 5UL,
  RKLCapturesArrayOp                 = 6UL,
  RKLDictionaryOfCapturesOp          = 7UL,
  RKLArrayOfDictionariesOfCapturesOp = 8UL,
  RKLMaskOp                          = 0xFUL,
  RKLReplaceMutable                  = 1UL << 4,
  RKLSubcapturesArray                = 1UL << 5,
};
typedef NSUInteger RKLRegexOp;

enum {
  RKLBlockEnumerationMatchOp   = 1UL,
  RKLBlockEnumerationReplaceOp = 2UL,
};
typedef NSUInteger RKLBlockEnumerationOp;

typedef struct {
  RKL_STRONG_REF NSRange    * RKL_GC_VOLATILE ranges;
                 NSRange                      findInRange, remainingRange;
                 NSInteger                    capacity, found, findUpTo, capture, addedSplitRanges;
                 size_t                       size, stackUsed;
  RKL_STRONG_REF void      ** RKL_GC_VOLATILE rangesScratchBuffer;
  RKL_STRONG_REF void      ** RKL_GC_VOLATILE stringsScratchBuffer;
  RKL_STRONG_REF void      ** RKL_GC_VOLATILE arraysScratchBuffer;
  RKL_STRONG_REF void      ** RKL_GC_VOLATILE dictionariesScratchBuffer;
  RKL_STRONG_REF void      ** RKL_GC_VOLATILE keysScratchBuffer;
} RKLFindAll;

typedef struct {
                 CFStringRef               string;
                 CFHashCode                hash;
                 CFIndex                   length;
  RKL_STRONG_REF UniChar * RKL_GC_VOLATILE uniChar;
} RKLBuffer;

typedef struct {
                 CFStringRef                     regexString;
                 CFHashCode                      regexHash;
                 RKLRegexOptions                 options;
                 uregex                         *icu_regex;
                 NSInteger                       captureCount;
  
                 CFStringRef                     setToString;
                 CFHashCode                      setToHash;
                 CFIndex                         setToLength;
                 NSUInteger                      setToIsImmutable:1;
                 NSUInteger                      setToNeedsConversion:1;
  RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE setToUniChar;
                 NSRange                         setToRange, lastFindRange, lastMatchRange;

                 RKLBuffer                      *buffer;
} RKLCachedRegex;

////////////
#pragma mark -
#pragma mark Translation unit scope global variables

static RKLLRUCacheSet_t     rkl_lruFixedBufferCacheSet = _RKL_LRU_CACHE_SET_INIT, rkl_lruDynamicBufferCacheSet = _RKL_LRU_CACHE_SET_INIT;
static RKLBuffer            rkl_lruDynamicBuffer[_RKL_LRU_CACHE_SET_WAYS];
static UniChar              rkl_lruFixedUniChar[_RKL_LRU_CACHE_SET_WAYS][_RKL_FIXED_LENGTH]; // This is the fixed sized UTF-16 conversion buffer.
static RKLBuffer            rkl_lruFixedBuffer[_RKL_LRU_CACHE_SET_WAYS] = {{NULL, 0UL, 0L, &rkl_lruFixedUniChar[0][0]}, {NULL, 0UL, 0L, &rkl_lruFixedUniChar[1][0]}, {NULL, 0UL, 0L, &rkl_lruFixedUniChar[2][0]}, {NULL, 0UL, 0L, &rkl_lruFixedUniChar[3][0]}};
static RKLCachedRegex       rkl_cachedRegexes[_RKL_REGEX_CACHE_LINES];
#if       defined(__GNUC__) && (__GNUC__ == 4) && defined(__GNUC_MINOR__) && (__GNUC_MINOR__ == 2)
static RKLCachedRegex * volatile rkl_lastCachedRegex; // XXX This is a work around for what appears to be a optimizer code generation bug in GCC 4.2.
#else
static RKLCachedRegex *rkl_lastCachedRegex;
#endif // defined(__GNUC__) && (__GNUC__ == 4) && defined(__GNUC_MINOR__) && (__GNUC_MINOR__ == 2)
static RKLLRUCacheSet_t     rkl_cachedRegexCacheSets[_RKL_REGEX_LRU_CACHE_SETS] = { [0 ... (_RKL_REGEX_LRU_CACHE_SETS - 1UL)] = _RKL_LRU_CACHE_SET_INIT };
static RKLLookasideCache_t  rkl_regexLookasideCache[_RKL_REGEX_LOOKASIDE_CACHE_SIZE] RKL_ALIGNED(64);
static OSSpinLock           rkl_cacheSpinLock = OS_SPINLOCK_INIT;
static const UniChar        rkl_emptyUniCharString[1];                                // For safety, icu_regexes are 'set' to this when the string they were searched is cleared.
static RKL_STRONG_REF void * RKL_GC_VOLATILE rkl_scratchBuffer[_RKL_SCRATCH_BUFFERS]; // Used to hold temporary allocations that are allocated via reallocf().

////////////
#pragma mark -
#pragma mark CFArray and CFDictionary call backs

// These are used when running under manual memory management for the array that rkl_splitArray creates.
// The split strings are created, but not autoreleased.  The (immutable) array is created using these callbacks, which skips the CFRetain() call, effectively transferring ownership to the CFArray object.
// For each split string this saves the overhead of an autorelease, then an array retain, then an NSAutoreleasePool release. This is good for a ~30% speed increase.

static void  rkl_CFCallbackRelease(CFAllocatorRef allocator RKL_UNUSED_ARG, const void *ptr) { CFRelease((CFTypeRef)ptr);                                                   }
static const CFArrayCallBacks           rkl_transferOwnershipArrayCallBacks           =      { (CFIndex)0L, NULL, rkl_CFCallbackRelease, CFCopyDescription, CFEqual         };
static const CFDictionaryKeyCallBacks   rkl_transferOwnershipDictionaryKeyCallBacks   =      { (CFIndex)0L, NULL, rkl_CFCallbackRelease, CFCopyDescription, CFEqual, CFHash };
static const CFDictionaryValueCallBacks rkl_transferOwnershipDictionaryValueCallBacks =      { (CFIndex)0L, NULL, rkl_CFCallbackRelease, CFCopyDescription, CFEqual         };

#ifdef    __OBJC_GC__
////////////
#pragma mark -
#pragma mark Low-level Garbage Collection aware memory/resource allocation utilities
// If compiled with Garbage Collection, we need to be able to do a few things slightly differently.
// The basic premiss is that under GC we use a trampoline function pointer which is set to a _start function to catch the first invocation.
// The _start function checks if GC is running and then overwrites the function pointer with the appropriate routine.  Think of it as 'lazy linking'.

enum { RKLScannedOption = NSScannedOption };

// rkl_collectingEnabled uses objc_getClass() to get the NSGarbageCollector class, which doesn't exist on earlier systems.
// This allows for graceful failure should we find ourselves running on an earlier version of the OS without NSGarbageCollector.
static BOOL  rkl_collectingEnabled_first (void);
static BOOL  rkl_collectingEnabled_yes   (void) { return(YES); }
static BOOL  rkl_collectingEnabled_no    (void) { return(NO);  }
static BOOL(*rkl_collectingEnabled)      (void) = rkl_collectingEnabled_first;
static BOOL  rkl_collectingEnabled_first (void) {
  BOOL gcEnabled = ([objc_getClass("NSGarbageCollector") defaultCollector] != NULL) ? YES : NO;
  if(gcEnabled == YES) {
    // This section of code is required due to what I consider to be a fundamental design flaw in Cocoas GC system.
    // Earlier versions of "Garbage Collection Programming Guide" stated that (paraphrased) "all globals are automatically roots".
    // Current versions of the guide now include the following warning:
    //    "You may pass addresses of strong globals or statics into routines expecting pointers to object pointers (such as id* or NSError**)
    //     only if they have first been assigned to directly, rather than through a pointer dereference."
    // This is a surprisingly non-trivial condition to actually meet in practice and is a recipe for impossible to debug race condition bugs.
    // We just happen to be very, very, very lucky in the fact that we can initialize our root set before the first use.
    NSUInteger x = 0UL;
    for(x = 0UL; x < _RKL_SCRATCH_BUFFERS; x++)    { rkl_scratchBuffer[x]            = NSAllocateCollectable(16UL, 0UL); rkl_scratchBuffer[x]            = NULL; }
    for(x = 0UL; x < _RKL_LRU_CACHE_SET_WAYS; x++) { rkl_lruDynamicBuffer[x].uniChar = NSAllocateCollectable(16UL, 0UL); rkl_lruDynamicBuffer[x].uniChar = NULL; }
  }
  return((rkl_collectingEnabled = (gcEnabled == YES) ? rkl_collectingEnabled_yes : rkl_collectingEnabled_no)());
}

// rkl_realloc()
static void   *rkl_realloc_first (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr, size_t size, NSUInteger flags);
static void   *rkl_realloc_std   (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr, size_t size, NSUInteger flags RKL_UNUSED_ARG) { return((*ptr = reallocf(*ptr, size))); }
static void   *rkl_realloc_gc    (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr, size_t size, NSUInteger flags)                { return((*ptr = NSReallocateCollectable(*ptr, (NSUInteger)size, flags))); }
static void *(*rkl_realloc)      (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr, size_t size, NSUInteger flags) RKL_ALLOC_SIZE_NON_NULL_ARGS_WARN_UNUSED(2,1) = rkl_realloc_first;
static void   *rkl_realloc_first (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr, size_t size, NSUInteger flags)                { if(rkl_collectingEnabled()==YES) { rkl_realloc = rkl_realloc_gc; } else { rkl_realloc = rkl_realloc_std; } return(rkl_realloc(ptr, size, flags)); }

// rkl_free()
static void *  rkl_free_first (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr);
static void *  rkl_free_std   (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr) { if(*ptr != NULL) { free(*ptr); *ptr = NULL; } return(NULL); }
static void *  rkl_free_gc    (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr) { if(*ptr != NULL) {             *ptr = NULL; } return(NULL); }
static void *(*rkl_free)      (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr) RKL_NONNULL_ARGS(1) = rkl_free_first;
static void   *rkl_free_first (RKL_STRONG_REF void ** RKL_GC_VOLATILE ptr) { if(rkl_collectingEnabled()==YES) { rkl_free = rkl_free_gc; } else { rkl_free = rkl_free_std; } return(rkl_free(ptr)); }

// rkl_CFAutorelease()
static id  rkl_CFAutorelease_first (CFTypeRef obj);
static id  rkl_CFAutorelease_std   (CFTypeRef obj) { return([(id)obj autorelease]);  }
static id  rkl_CFAutorelease_gc    (CFTypeRef obj) { return(NSMakeCollectable(obj)); }
static id(*rkl_CFAutorelease)      (CFTypeRef obj) = rkl_CFAutorelease_first;
static id  rkl_CFAutorelease_first (CFTypeRef obj) { return((rkl_CFAutorelease = (rkl_collectingEnabled()==YES) ? rkl_CFAutorelease_gc : rkl_CFAutorelease_std)(obj)); }

// rkl_CreateStringWithSubstring()
static id  rkl_CreateStringWithSubstring_first (id string, NSRange range);
static id  rkl_CreateStringWithSubstring_std   (id string, NSRange range) { return((id)CFStringCreateWithSubstring(NULL, (CFStringRef)string, CFMakeRange((CFIndex)range.location, (CFIndex)range.length))); }
static id  rkl_CreateStringWithSubstring_gc    (id string, NSRange range) { return([string substringWithRange:range]); }
static id(*rkl_CreateStringWithSubstring)      (id string, NSRange range) RKL_WARN_UNUSED_NONNULL_ARGS(1) = rkl_CreateStringWithSubstring_first;
static id  rkl_CreateStringWithSubstring_first (id string, NSRange range) { return((rkl_CreateStringWithSubstring = (rkl_collectingEnabled()==YES) ? rkl_CreateStringWithSubstring_gc : rkl_CreateStringWithSubstring_std)(string, range)); }

// rkl_ReleaseObject()
static id   rkl_ReleaseObject_first (id obj);
static id   rkl_ReleaseObject_std   (id obj)                { CFRelease((CFTypeRef)obj); return(NULL); }
static id   rkl_ReleaseObject_gc    (id obj RKL_UNUSED_ARG) {                            return(NULL); }
static id (*rkl_ReleaseObject)      (id obj) RKL_NONNULL_ARGS(1) = rkl_ReleaseObject_first;
static id   rkl_ReleaseObject_first (id obj)                { return((rkl_ReleaseObject = (rkl_collectingEnabled()==YES) ? rkl_ReleaseObject_gc : rkl_ReleaseObject_std)(obj)); }

// rkl_CreateArrayWithObjects()
static id  rkl_CreateArrayWithObjects_first (void **objects, NSUInteger count);
static id  rkl_CreateArrayWithObjects_std   (void **objects, NSUInteger count) { return((id)CFArrayCreate(NULL, (const void **)objects, (CFIndex)count, &rkl_transferOwnershipArrayCallBacks)); }
static id  rkl_CreateArrayWithObjects_gc    (void **objects, NSUInteger count) { return([NSArray arrayWithObjects:(const id *)objects count:count]); }
static id(*rkl_CreateArrayWithObjects)      (void **objects, NSUInteger count) RKL_WARN_UNUSED_NONNULL_ARGS(1) = rkl_CreateArrayWithObjects_first;
static id  rkl_CreateArrayWithObjects_first (void **objects, NSUInteger count) { return((rkl_CreateArrayWithObjects = (rkl_collectingEnabled()==YES) ? rkl_CreateArrayWithObjects_gc : rkl_CreateArrayWithObjects_std)(objects, count)); }

// rkl_CreateAutoreleasedArray()
static id  rkl_CreateAutoreleasedArray_first (void **objects, NSUInteger count);
static id  rkl_CreateAutoreleasedArray_std   (void **objects, NSUInteger count) { return((id)rkl_CFAutorelease(rkl_CreateArrayWithObjects(objects, count))); }
static id  rkl_CreateAutoreleasedArray_gc    (void **objects, NSUInteger count) { return(                      rkl_CreateArrayWithObjects(objects, count) ); }
static id(*rkl_CreateAutoreleasedArray)      (void **objects, NSUInteger count) RKL_WARN_UNUSED_NONNULL_ARGS(1) = rkl_CreateAutoreleasedArray_first;
static id  rkl_CreateAutoreleasedArray_first (void **objects, NSUInteger count) { return((rkl_CreateAutoreleasedArray = (rkl_collectingEnabled()==YES) ? rkl_CreateAutoreleasedArray_gc : rkl_CreateAutoreleasedArray_std)(objects, count)); }

#else  // __OBJC_GC__ not defined
////////////
#pragma mark -
#pragma mark Low-level explicit memory/resource allocation utilities

enum { RKLScannedOption = 0 };

#define rkl_collectingEnabled() (NO)

RKL_STATIC_INLINE void *rkl_realloc                   (void **ptr, size_t size, NSUInteger flags) RKL_ALLOC_SIZE_NON_NULL_ARGS_WARN_UNUSED(2,1);
RKL_STATIC_INLINE void *rkl_free                      (void **ptr)                                RKL_NONNULL_ARGS(1);
RKL_STATIC_INLINE id    rkl_CFAutorelease             (CFTypeRef obj)                             RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE id    rkl_CreateAutoreleasedArray   (void **objects, NSUInteger count)          RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE id    rkl_CreateArrayWithObjects    (void **objects, NSUInteger count)          RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE id    rkl_CreateStringWithSubstring (id string, NSRange range)                  RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE id    rkl_ReleaseObject             (id obj)                                    RKL_NONNULL_ARGS(1);

RKL_STATIC_INLINE void *rkl_realloc                   (void **ptr, size_t size, NSUInteger flags RKL_UNUSED_ARG) { return((*ptr = reallocf(*ptr, size))); }
RKL_STATIC_INLINE void *rkl_free                      (void **ptr)                                               { if(*ptr != NULL) { free(*ptr); *ptr = NULL; } return(NULL); }
RKL_STATIC_INLINE id    rkl_CFAutorelease             (CFTypeRef obj)                                            { return([(id)obj autorelease]); }
RKL_STATIC_INLINE id    rkl_CreateArrayWithObjects    (void **objects, NSUInteger count)                         { return((id)CFArrayCreate(NULL, (const void **)objects, (CFIndex)count, &rkl_transferOwnershipArrayCallBacks)); }
RKL_STATIC_INLINE id    rkl_CreateAutoreleasedArray   (void **objects, NSUInteger count)                         { return(rkl_CFAutorelease(rkl_CreateArrayWithObjects(objects, count))); }
RKL_STATIC_INLINE id    rkl_CreateStringWithSubstring (id string, NSRange range)                                 { return((id)CFStringCreateWithSubstring(NULL, (CFStringRef)string, CFMakeRange((CFIndex)range.location, (CFIndex)range.length))); }
RKL_STATIC_INLINE id    rkl_ReleaseObject             (id obj)                                                   { CFRelease((CFTypeRef)obj); return(NULL); }

#endif // __OBJC_GC__

////////////
#pragma mark -
#pragma mark ICU function prototypes

// ICU functions.  See http://www.icu-project.org/apiref/icu4c/uregex_8h.html Tweaked slightly from the originals, but functionally identical.
const char *RKL_ICU_FUNCTION_APPEND(u_errorName)              (                                                                                                                             int32_t  status) RKL_WARN_UNUSED_PURE;
int32_t     RKL_ICU_FUNCTION_APPEND(u_strlen)                 (const UniChar *s)                                                                                                                             RKL_WARN_UNUSED_PURE_NONNULL_ARGS(1);
int32_t     RKL_ICU_FUNCTION_APPEND(uregex_appendReplacement) (      uregex  *regexp,  const UniChar *replacementText, int32_t replacementLength, UniChar **destBuf, int32_t *destCapacity, int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2,4,5,6);
int32_t     RKL_ICU_FUNCTION_APPEND(uregex_appendTail)        (      uregex  *regexp,                                                             UniChar **destBuf, int32_t *destCapacity, int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2,3,4);
void        RKL_ICU_FUNCTION_APPEND(uregex_close)             (      uregex  *regexp)                                                                                                                        RKL_NONNULL_ARGS(1);
int32_t     RKL_ICU_FUNCTION_APPEND(uregex_end)               (      uregex  *regexp,  int32_t groupNum,                                                                                    int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,3);
BOOL        RKL_ICU_FUNCTION_APPEND(uregex_find)              (      uregex  *regexp,  int32_t location,                                                                                    int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,3);
BOOL        RKL_ICU_FUNCTION_APPEND(uregex_findNext)          (      uregex  *regexp,                                                                                                       int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2);
int32_t     RKL_ICU_FUNCTION_APPEND(uregex_groupCount)        (      uregex  *regexp,                                                                                                       int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2);
uregex     *RKL_ICU_FUNCTION_APPEND(uregex_open)              (const UniChar *pattern, int32_t patternLength, RKLRegexOptions flags, UParseError *parseError,                               int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,4,5);
void        RKL_ICU_FUNCTION_APPEND(uregex_reset)             (      uregex  *regexp,  int32_t newIndex,                                                                                    int32_t *status) RKL_NONNULL_ARGS(1,3);
void        RKL_ICU_FUNCTION_APPEND(uregex_setText)           (      uregex  *regexp,  const UniChar *text, int32_t textLength,                                                             int32_t *status) RKL_NONNULL_ARGS(1,2,4);
int32_t     RKL_ICU_FUNCTION_APPEND(uregex_start)             (      uregex  *regexp,  int32_t groupNum,                                                                                    int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,3);
uregex     *RKL_ICU_FUNCTION_APPEND(uregex_clone)             (const uregex  *regexp,                                                                                                       int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2);

////////////
#pragma mark -
#pragma mark RegexKitLite internal, private function prototypes

// Functions used for managing the 4-way set associative LRU cache and regex string hash lookaside cache.
RKL_STATIC_INLINE NSUInteger      rkl_leastRecentlyUsedWayInSet                          (      NSUInteger      cacheSetsCount, const RKLLRUCacheSet_t cacheSetsArray[cacheSetsCount], NSUInteger set)                  RKL_WARN_UNUSED_NONNULL_ARGS(2);
RKL_STATIC_INLINE void            rkl_accessCacheSetWay                                  (      NSUInteger      cacheSetsCount,       RKLLRUCacheSet_t cacheSetsArray[cacheSetsCount], NSUInteger set, NSUInteger way)  RKL_NONNULL_ARGS(2);
RKL_STATIC_INLINE NSUInteger      rkl_regexLookasideCacheIndexForPointerAndOptions       (const void           *ptr,         RKLRegexOptions options)                                                                   RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE void            rkl_setRegexLookasideCacheToCachedRegexForPointer      (const RKLCachedRegex *cachedRegex, const void *ptr)                                                                           RKL_NONNULL_ARGS(1,2);
RKL_STATIC_INLINE RKLCachedRegex *rkl_cachedRegexFromRegexLookasideCacheForString        (const void           *ptr,         RKLRegexOptions options)                                                                   RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE NSUInteger      rkl_makeCacheSetHash                                   (      CFHashCode      regexHash,   RKLRegexOptions options)                                                                   RKL_WARN_UNUSED;
RKL_STATIC_INLINE NSUInteger      rkl_cacheSetForRegexHashAndOptions                     (      CFHashCode      regexHash,   RKLRegexOptions options)                                                                   RKL_WARN_UNUSED;
RKL_STATIC_INLINE NSUInteger      rkl_cacheWayForCachedRegex                             (const RKLCachedRegex *cachedRegex)                                                                                            RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE NSUInteger      rkl_cacheSetForCachedRegex                             (const RKLCachedRegex *cachedRegex)                                                                                            RKL_WARN_UNUSED_NONNULL_ARGS(1);
RKL_STATIC_INLINE RKLCachedRegex *rkl_cachedRegexForCacheSetAndWay                       (      NSUInteger      cacheSet,    NSUInteger      cacheWay)                                                                  RKL_WARN_UNUSED;
RKL_STATIC_INLINE RKLCachedRegex *rkl_cachedRegexForRegexHashAndOptionsAndWay            (      CFHashCode      regexHash,   RKLRegexOptions options, NSUInteger cacheWay)                                              RKL_WARN_UNUSED;
RKL_STATIC_INLINE void            rkl_updateCachesWithCachedRegex                        (      RKLCachedRegex *cachedRegex, const void *ptr, int hitOrMiss RKL_UNUSED_DTRACE_ARG, int status RKL_UNUSED_DTRACE_ARG)    RKL_NONNULL_ARGS(1,2);
RKL_STATIC_INLINE RKLCachedRegex *rkl_leastRecentlyUsedCachedRegexForRegexHashAndOptions (      CFHashCode      regexHash,   RKLRegexOptions options)                                                                   RKL_WARN_UNUSED;

static RKLCachedRegex *rkl_getCachedRegex            (NSString *regexString, RKLRegexOptions options, NSError **error, id *exception)                                                                                                                            RKL_WARN_UNUSED_NONNULL_ARGS(1,4);
static NSUInteger      rkl_setCachedRegexToString    (RKLCachedRegex *cachedRegex, const NSRange *range, int32_t *status, id *exception RKL_UNUSED_ASSERTION_ARG)                                                                                                    RKL_WARN_UNUSED_NONNULL_ARGS(1,2,3,4);
static RKLCachedRegex *rkl_getCachedRegexSetToString (NSString *regexString, RKLRegexOptions options, NSString *matchString, NSUInteger *matchLengthPtr, NSRange *matchRange, NSError **error, id *exception, int32_t *status)                                   RKL_WARN_UNUSED_NONNULL_ARGS(1,3,4,5,7,8);
static id              rkl_performDictionaryVarArgsOp(id self, SEL _cmd, RKLRegexOp regexOp, NSString *regexString, RKLRegexOptions options, NSInteger capture, id matchString, NSRange *matchRange, NSString *replacementString, NSError **error, void *result, id firstKey, va_list varArgsList) RKL_NONNULL_ARGS(1,2);
static id              rkl_performRegexOp            (id self, SEL _cmd, RKLRegexOp regexOp, NSString *regexString, RKLRegexOptions options, NSInteger capture, id matchString, NSRange *matchRange, NSString *replacementString, NSError **error, void *result, NSUInteger captureKeysCount, id captureKeys[captureKeysCount], const int captureKeyIndexes[captureKeysCount]) RKL_NONNULL_ARGS(1,2);
static void            rkl_handleDelayedAssert       (id self, SEL _cmd, id exception)                                                                                                                                                                           RKL_NONNULL_ARGS(3);

static NSUInteger      rkl_search                    (RKLCachedRegex *cachedRegex, NSRange *searchRange, NSUInteger updateSearchRange, id *exception RKL_UNUSED_ASSERTION_ARG, int32_t *status)                        RKL_WARN_UNUSED_NONNULL_ARGS(1,2,4,5);

static BOOL            rkl_findRanges                (RKLCachedRegex *cachedRegex, RKLRegexOp regexOp,      RKLFindAll *findAll, id *exception, int32_t *status)                                                       RKL_WARN_UNUSED_NONNULL_ARGS(1,3,4,5);
static NSUInteger      rkl_growFindRanges            (RKLCachedRegex *cachedRegex, NSUInteger lastLocation, RKLFindAll *findAll, id *exception RKL_UNUSED_ASSERTION_ARG)                                               RKL_WARN_UNUSED_NONNULL_ARGS(1,3,4);
static NSArray        *rkl_makeArray                 (RKLCachedRegex *cachedRegex, RKLRegexOp regexOp,      RKLFindAll *findAll, id *exception RKL_UNUSED_ASSERTION_ARG)                                               RKL_WARN_UNUSED_NONNULL_ARGS(1,3,4);
static id              rkl_makeDictionary            (RKLCachedRegex *cachedRegex, RKLRegexOp regexOp,      RKLFindAll *findAll, NSUInteger captureKeysCount, id captureKeys[captureKeysCount], const int captureKeyIndexes[captureKeysCount], id *exception RKL_UNUSED_ASSERTION_ARG) RKL_WARN_UNUSED_NONNULL_ARGS(1,3,5,6);

static NSString       *rkl_replaceString             (RKLCachedRegex *cachedRegex, id searchString, NSUInteger searchU16Length, NSString *replacementString, NSUInteger replacementU16Length, NSInteger *replacedCount, NSUInteger replaceMutable, id *exception, int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2,4,8,9);
static int32_t         rkl_replaceAll                (RKLCachedRegex *cachedRegex, RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE replacementUniChar, int32_t replacementU16Length, UniChar *replacedUniChar, int32_t replacedU16Capacity, NSInteger *replacedCount, int32_t *needU16Capacity, id *exception RKL_UNUSED_ASSERTION_ARG, int32_t *status) RKL_WARN_UNUSED_NONNULL_ARGS(1,2,4,6,7,8,9);

static NSUInteger      rkl_isRegexValid              (id self, SEL _cmd, NSString *regex, RKLRegexOptions options, NSInteger *captureCountPtr, NSError **error) RKL_NONNULL_ARGS(1,2);

static void            rkl_clearStringCache          (void);
static void            rkl_clearBuffer               (RKLBuffer *buffer, NSUInteger freeDynamicBuffer) RKL_NONNULL_ARGS(1);
static void            rkl_clearCachedRegex          (RKLCachedRegex *cachedRegex)                     RKL_NONNULL_ARGS(1);
static void            rkl_clearCachedRegexSetTo     (RKLCachedRegex *cachedRegex)                     RKL_NONNULL_ARGS(1);

static NSDictionary   *rkl_userInfoDictionary        (RKLUserInfoOptions userInfoOptions, NSString *regexString, RKLRegexOptions options, const UParseError *parseError, int32_t status, NSString *matchString, NSRange matchRange, NSString *replacementString, NSString *replacedString, NSInteger replacedCount, RKLRegexEnumerationOptions enumerationOptions, ...)                        RKL_WARN_UNUSED_SENTINEL;
static NSError        *rkl_makeNSError               (RKLUserInfoOptions userInfoOptions, NSString *regexString, RKLRegexOptions options, const UParseError *parseError, int32_t status, NSString *matchString, NSRange matchRange, NSString *replacementString, NSString *replacedString, NSInteger replacedCount, RKLRegexEnumerationOptions enumerationOptions, NSString *errorDescription) RKL_WARN_UNUSED;

static NSException    *rkl_NSExceptionForRegex       (NSString *regexString, RKLRegexOptions options, const UParseError *parseError, int32_t status) RKL_WARN_UNUSED_NONNULL_ARGS(1);
static NSDictionary   *rkl_makeAssertDictionary      (const char *function, const char *file, int line, NSString *format, ...)                       RKL_WARN_UNUSED_NONNULL_ARGS(1,2,4);
static NSString       *rkl_stringFromClassAndMethod  (id object, SEL selector, NSString *format, ...)                                                RKL_WARN_UNUSED_NONNULL_ARGS(3);

RKL_STATIC_INLINE int32_t rkl_getRangeForCapture(RKLCachedRegex *cr, int32_t *s, int32_t c, NSRange *r) RKL_WARN_UNUSED_NONNULL_ARGS(1,2,4);
RKL_STATIC_INLINE int32_t rkl_getRangeForCapture(RKLCachedRegex *cr, int32_t *s, int32_t c, NSRange *r) { uregex *re = cr->icu_regex; int32_t start = RKL_ICU_FUNCTION_APPEND(uregex_start)(re, c, s); if(RKL_EXPECTED((*s > U_ZERO_ERROR), 0L) || (start == -1)) { *r = NSNotFoundRange; } else { r->location = (NSUInteger)start; r->length = (NSUInteger)RKL_ICU_FUNCTION_APPEND(uregex_end)(re, c, s) - r->location; r->location += cr->setToRange.location; } return(*s); }

RKL_STATIC_INLINE RKLFindAll rkl_makeFindAll(RKL_STRONG_REF NSRange * RKL_GC_VOLATILE r, NSRange fir, NSInteger c, size_t s, size_t su, RKL_STRONG_REF void ** RKL_GC_VOLATILE rsb, RKL_STRONG_REF void ** RKL_GC_VOLATILE ssb, RKL_STRONG_REF void ** RKL_GC_VOLATILE asb, RKL_STRONG_REF void ** RKL_GC_VOLATILE dsb, RKL_STRONG_REF void ** RKL_GC_VOLATILE ksb, NSInteger f, NSInteger cap, NSInteger fut) RKL_WARN_UNUSED_CONST;
RKL_STATIC_INLINE RKLFindAll rkl_makeFindAll(RKL_STRONG_REF NSRange * RKL_GC_VOLATILE r, NSRange fir, NSInteger c, size_t s, size_t su, RKL_STRONG_REF void ** RKL_GC_VOLATILE rsb, RKL_STRONG_REF void ** RKL_GC_VOLATILE ssb, RKL_STRONG_REF void ** RKL_GC_VOLATILE asb, RKL_STRONG_REF void ** RKL_GC_VOLATILE dsb, RKL_STRONG_REF void ** RKL_GC_VOLATILE ksb, NSInteger f, NSInteger cap, NSInteger fut) { return(((RKLFindAll){ .ranges=r, .findInRange=fir, .remainingRange=fir, .capacity=c, .found=f, .findUpTo=fut, .capture=cap, .addedSplitRanges=0L, .size=s, .stackUsed=su, .rangesScratchBuffer=rsb, .stringsScratchBuffer=ssb, .arraysScratchBuffer=asb, .dictionariesScratchBuffer=dsb, .keysScratchBuffer=ksb})); }

////////////
#pragma mark -
#pragma mark RKL_FAST_MUTABLE_CHECK implementation

#ifdef RKL_FAST_MUTABLE_CHECK
// We use a trampoline function pointer to check at run time if the function __CFStringIsMutable is available.
// If it is, the trampoline function pointer is replaced with the address of that function.
// Otherwise, we assume the worst case that every string is mutable.
// This hopefully helps to protect us since we're using an undocumented, non-public API call.
// We will keep on working if it ever does go away, just with a bit less performance due to the overhead of mutable checks.

static BOOL  rkl_CFStringIsMutable_first (CFStringRef str);
static BOOL  rkl_CFStringIsMutable_yes   (CFStringRef str RKL_UNUSED_ARG) { return(YES); }
static BOOL(*rkl_CFStringIsMutable)      (CFStringRef str) = rkl_CFStringIsMutable_first;
static BOOL  rkl_CFStringIsMutable_first (CFStringRef str)                { if((rkl_CFStringIsMutable = (BOOL(*)(CFStringRef))dlsym(RTLD_DEFAULT, "__CFStringIsMutable")) == NULL) { rkl_CFStringIsMutable = rkl_CFStringIsMutable_yes; } return(rkl_CFStringIsMutable(str)); }
#else  // RKL_FAST_MUTABLE_CHECK is not defined.  Assume that all strings are potentially mutable.
#define rkl_CFStringIsMutable(s) (YES)
#endif // RKL_FAST_MUTABLE_CHECK

////////////
#pragma mark -
#pragma mark iPhone / iPod touch low memory notification handler

#if       defined(RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS) && (RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS == 1)

// The next few lines are specifically for the iPhone to catch low memory conditions.
// The basic idea is that rkl_RegisterForLowMemoryNotifications() is set to be run once by the linker at load time via __attribute((constructor)).
// rkl_RegisterForLowMemoryNotifications() tries to find the iPhone low memory notification symbol.  If it can find it,
// it registers with the default NSNotificationCenter to call the RKLLowMemoryWarningObserver class method +lowMemoryWarning:.
// rkl_RegisterForLowMemoryNotifications() uses an atomic compare and swap to guarantee that it initializes exactly once.
// +lowMemoryWarning tries to acquire the cache lock.  If it gets the lock, it clears the cache.  If it can't, it calls performSelector:
// with a delay of half a second to try again.  This will hopefully prevent any deadlocks, such as a RegexKitLite request for
// memory triggering a notification while the lock is held.

static void rkl_RegisterForLowMemoryNotifications(void) RKL_ATTRIBUTES(used);

@interface      RKLLowMemoryWarningObserver : NSObject +(void)lowMemoryWarning:(id)notification; @end
@implementation RKLLowMemoryWarningObserver
+(void)lowMemoryWarning:(id)notification {
  if(OSSpinLockTry(&rkl_cacheSpinLock)) { rkl_clearStringCache(); OSSpinLockUnlock(&rkl_cacheSpinLock); }
  else { [[RKLLowMemoryWarningObserver class] performSelector:@selector(lowMemoryWarning:) withObject:notification afterDelay:(NSTimeInterval)0.1]; }
}
@end

static volatile int rkl_HaveRegisteredForLowMemoryNotifications = 0;

__attribute__((constructor)) static void rkl_RegisterForLowMemoryNotifications(void) {
  _Bool   didSwap                   = false;
  void  **memoryWarningNotification = NULL;

  while((rkl_HaveRegisteredForLowMemoryNotifications == 0) && ((didSwap = OSAtomicCompareAndSwapIntBarrier(0, 1, &rkl_HaveRegisteredForLowMemoryNotifications)) == false)) { /* Allows for spurious CAS failures. */ }
  if(didSwap == true) {
    if((memoryWarningNotification = (void **)dlsym(RTLD_DEFAULT, "UIApplicationDidReceiveMemoryWarningNotification")) != NULL) {
      [[NSNotificationCenter defaultCenter] addObserver:[RKLLowMemoryWarningObserver class] selector:@selector(lowMemoryWarning:) name:(NSString *)*memoryWarningNotification object:NULL];
    }
  }
}

#endif // defined(RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS) && (RKL_REGISTER_FOR_IPHONE_LOWMEM_NOTIFICATIONS == 1)

////////////
#pragma mark -
#pragma mark DTrace functionality

#ifdef    _RKL_DTRACE_ENABLED

// compiledRegexCache(unsigned long eventID, const char *regexUTF8, int options, int captures, int hitMiss, int icuStatusCode, const char *icuErrorMessage, double *hitRate);
// utf16ConversionCache(unsigned long eventID, unsigned int lookupResultFlags, double *hitRate, const void *string, unsigned long NSRange.location, unsigned long NSRange.length, long length);

/*
provider RegexKitLite {
 probe compiledRegexCache(unsigned long, const char *, unsigned int, int, int, int, const char *, double *);
 probe utf16ConversionCache(unsigned long, unsigned int, double *, const void *, unsigned long, unsigned long, long);
};
 
#pragma D attributes Unstable/Unstable/Common provider RegexKitLite provider
#pragma D attributes Private/Private/Common   provider RegexKitLite module
#pragma D attributes Private/Private/Common   provider RegexKitLite function
#pragma D attributes Unstable/Unstable/Common provider RegexKitLite name
#pragma D attributes Unstable/Unstable/Common provider RegexKitLite args
*/

#define REGEXKITLITE_STABILITY "___dtrace_stability$RegexKitLite$v1$4_4_5_1_1_5_1_1_5_4_4_5_4_4_5"
#define REGEXKITLITE_TYPEDEFS  "___dtrace_typedefs$RegexKitLite$v1"
#define REGEXKITLITE_COMPILEDREGEXCACHE(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) { __asm__ volatile(".reference " REGEXKITLITE_TYPEDEFS); __dtrace_probe$RegexKitLite$compiledRegexCache$v1$756e7369676e6564206c6f6e67$63686172202a$756e7369676e656420696e74$696e74$696e74$696e74$63686172202a$646f75626c65202a(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7); __asm__ volatile(".reference " REGEXKITLITE_STABILITY); }
#define REGEXKITLITE_COMPILEDREGEXCACHE_ENABLED() __dtrace_isenabled$RegexKitLite$compiledRegexCache$v1()
#define	REGEXKITLITE_CONVERTEDSTRINGU16CACHE(arg0, arg1, arg2, arg3, arg4, arg5, arg6) { __asm__ volatile(".reference " REGEXKITLITE_TYPEDEFS); __dtrace_probe$RegexKitLite$utf16ConversionCache$v1$756e7369676e6564206c6f6e67$756e7369676e656420696e74$646f75626c65202a$766f6964202a$756e7369676e6564206c6f6e67$756e7369676e6564206c6f6e67$6c6f6e67(arg0, arg1, arg2, arg3, arg4, arg5, arg6); __asm__ volatile(".reference " REGEXKITLITE_STABILITY); }
#define	REGEXKITLITE_CONVERTEDSTRINGU16CACHE_ENABLED() __dtrace_isenabled$RegexKitLite$utf16ConversionCache$v1()

extern void __dtrace_probe$RegexKitLite$compiledRegexCache$v1$756e7369676e6564206c6f6e67$63686172202a$756e7369676e656420696e74$696e74$696e74$696e74$63686172202a$646f75626c65202a(unsigned long, const char *, unsigned int, int, int, int, const char *, double *);
extern int  __dtrace_isenabled$RegexKitLite$compiledRegexCache$v1(void);
extern void __dtrace_probe$RegexKitLite$utf16ConversionCache$v1$756e7369676e6564206c6f6e67$756e7369676e656420696e74$646f75626c65202a$766f6964202a$756e7369676e6564206c6f6e67$756e7369676e6564206c6f6e67$6c6f6e67(unsigned long, unsigned int, double *, const void *, unsigned long, unsigned long, long);
extern int  __dtrace_isenabled$RegexKitLite$utf16ConversionCache$v1(void);

////////////////////////////

enum {
  RKLCacheHitLookupFlag           = 1 << 0,
  RKLConversionRequiredLookupFlag = 1 << 1,
  RKLSetTextLookupFlag            = 1 << 2,
  RKLDynamicBufferLookupFlag      = 1 << 3,
  RKLErrorLookupFlag              = 1 << 4,
  RKLEnumerationBufferLookupFlag  = 1 << 5,
};

#define rkl_dtrace_addLookupFlag(a,b) do { a |= (unsigned int)(b); } while(0)

static char rkl_dtrace_regexUTF8[_RKL_REGEX_CACHE_LINES + 1UL][_RKL_DTRACE_REGEXUTF8_SIZE];
static NSUInteger rkl_dtrace_eventID, rkl_dtrace_compiledCacheLookups, rkl_dtrace_compiledCacheHits, rkl_dtrace_conversionBufferLookups, rkl_dtrace_conversionBufferHits;

#define rkl_dtrace_incrementEventID() do { rkl_dtrace_eventID++; } while(0)
#define rkl_dtrace_incrementAndGetEventID(v) do { rkl_dtrace_eventID++; v = rkl_dtrace_eventID; } while(0)
#define rkl_dtrace_compiledRegexCache(a0, a1, a2, a3, a4, a5) do { int _a3 = (a3); rkl_dtrace_compiledCacheLookups++; if(_a3 == 1) { rkl_dtrace_compiledCacheHits++; } if(RKL_EXPECTED(REGEXKITLITE_COMPILEDREGEXCACHE_ENABLED(), 0L)) { double hitRate = 0.0; if(rkl_dtrace_compiledCacheLookups > 0UL) { hitRate = ((double)rkl_dtrace_compiledCacheHits / (double)rkl_dtrace_compiledCacheLookups) * 100.0; } REGEXKITLITE_COMPILEDREGEXCACHE(rkl_dtrace_eventID, a0, a1, a2, _a3, a4, a5, &hitRate); } } while(0)
#define rkl_dtrace_utf16ConversionCache(a0, a1, a2, a3, a4) do { unsigned int _a0 = (a0); if((_a0 & RKLConversionRequiredLookupFlag) != 0U) { rkl_dtrace_conversionBufferLookups++; if((_a0 & RKLCacheHitLookupFlag) != 0U) { rkl_dtrace_conversionBufferHits++; } } if(RKL_EXPECTED(REGEXKITLITE_CONVERTEDSTRINGU16CACHE_ENABLED(), 0L)) { double hitRate = 0.0; if(rkl_dtrace_conversionBufferLookups > 0UL) { hitRate = ((double)rkl_dtrace_conversionBufferHits / (double)rkl_dtrace_conversionBufferLookups) * 100.0; } REGEXKITLITE_CONVERTEDSTRINGU16CACHE(rkl_dtrace_eventID, _a0, &hitRate, a1, a2, a3, a4); } } while(0)
#define rkl_dtrace_utf16ConversionCacheWithEventID(c0, a0, a1, a2, a3, a4) do { unsigned int _a0 = (a0); if((_a0 & RKLConversionRequiredLookupFlag) != 0U) { rkl_dtrace_conversionBufferLookups++; if((_a0 & RKLCacheHitLookupFlag) != 0U) { rkl_dtrace_conversionBufferHits++; } } if(RKL_EXPECTED(REGEXKITLITE_CONVERTEDSTRINGU16CACHE_ENABLED(), 0L)) { double hitRate = 0.0; if(rkl_dtrace_conversionBufferLookups > 0UL) { hitRate = ((double)rkl_dtrace_conversionBufferHits / (double)rkl_dtrace_conversionBufferLookups) * 100.0; } REGEXKITLITE_CONVERTEDSTRINGU16CACHE(c0, _a0, &hitRate, a1, a2, a3, a4); } } while(0)


// \342\200\246 == UTF8 for HORIZONTAL ELLIPSIS, aka triple dots '...'
#define RKL_UTF8_ELLIPSE "\342\200\246"

// rkl_dtrace_getRegexUTF8 will copy the str argument to utf8Buffer using UTF8 as the string encoding.
// If the utf8 encoding would take up more bytes than the utf8Buffers length, then the unicode character 'HORIZONTAL ELLIPSIS' ('...') is appended to indicate truncation occurred.
static void rkl_dtrace_getRegexUTF8(CFStringRef str, char *utf8Buffer) RKL_NONNULL_ARGS(2);
static void rkl_dtrace_getRegexUTF8(CFStringRef str, char *utf8Buffer) {
  if((str == NULL) || (utf8Buffer == NULL)) { return; }
  CFIndex maxLength = ((CFIndex)_RKL_DTRACE_REGEXUTF8_SIZE - 2L), maxBytes = (maxLength - (CFIndex)sizeof(RKL_UTF8_ELLIPSE) - 1L), stringU16Length = CFStringGetLength(str), usedBytes = 0L;
  CFStringGetBytes(str, CFMakeRange(0L, ((stringU16Length < maxLength) ? stringU16Length : maxLength)), kCFStringEncodingUTF8, (UInt8)'?', (Boolean)0, (UInt8 *)utf8Buffer, maxBytes, &usedBytes);
  if(usedBytes == maxBytes) { strncpy(utf8Buffer + usedBytes, RKL_UTF8_ELLIPSE, ((size_t)_RKL_DTRACE_REGEXUTF8_SIZE - (size_t)usedBytes) - 2UL); } else { utf8Buffer[usedBytes] = (char)0; }
}

#else  // _RKL_DTRACE_ENABLED

#define rkl_dtrace_incrementEventID()
#define rkl_dtrace_incrementAndGetEventID(v)
#define rkl_dtrace_compiledRegexCache(a0, a1, a2, a3, a4, a5)
#define rkl_dtrace_utf16ConversionCache(a0, a1, a2, a3, a4)
#define rkl_dtrace_utf16ConversionCacheWithEventID(c0, a0, a1, a2, a3, a4)
#define rkl_dtrace_getRegexUTF8(str, buf)
#define rkl_dtrace_addLookupFlag(a,b)

#endif // _RKL_DTRACE_ENABLED

////////////
#pragma mark -
#pragma mark RegexKitLite low-level internal functions
#pragma mark -

// The 4-way set associative LRU logic comes from Henry S. Warren Jr.'s Hacker's Delight, "revisions", 7-7 An LRU Algorithm:
// http://www.hackersdelight.org/revisions.pdf
// The functions rkl_leastRecentlyUsedWayInSet() and rkl_accessCacheSetWay() implement the cache functionality and are used
// from a number of different places that need to perform caching (i.e., cached regex, cached UTF16 conversions, etc)

#pragma mark 4-way set associative LRU functions

RKL_STATIC_INLINE NSUInteger rkl_leastRecentlyUsedWayInSet(NSUInteger cacheSetsCount, const RKLLRUCacheSet_t cacheSetsArray[cacheSetsCount], NSUInteger set) {
  RKLCAbortAssert((cacheSetsArray != NULL) && ((NSInteger)cacheSetsCount > 0L) && (set < cacheSetsCount) && ((cacheSetsArray == rkl_cachedRegexCacheSets) ? set < _RKL_REGEX_LRU_CACHE_SETS : 1) && (((sizeof(unsigned int) - sizeof(RKLLRUCacheSet_t)) * 8) < (sizeof(unsigned int) * 8)));
  unsigned int cacheSet = (((unsigned int)cacheSetsArray[set]) << ((sizeof(unsigned int) - sizeof(RKLLRUCacheSet_t)) * 8)); // __builtin_clz takes an 'unsigned int' argument.  The rest is to ensure bit alignment regardless of 32/64/whatever.
  NSUInteger leastRecentlyUsed = ((NSUInteger)(3LU - (NSUInteger)((__builtin_clz((~(((cacheSet & 0x77777777U) + 0x77777777U) | cacheSet | 0x77777777U))) ) >> 2)));
  RKLCAbortAssert(leastRecentlyUsed < _RKL_LRU_CACHE_SET_WAYS);
  return(leastRecentlyUsed);
}

RKL_STATIC_INLINE void rkl_accessCacheSetWay(NSUInteger cacheSetsCount, RKLLRUCacheSet_t cacheSetsArray[cacheSetsCount], NSUInteger cacheSet, NSUInteger cacheWay) {
  RKLCAbortAssert((cacheSetsArray != NULL) && ((NSInteger)cacheSetsCount > 0L) && (cacheSet < cacheSetsCount) && (cacheWay < _RKL_LRU_CACHE_SET_WAYS) && ((cacheSetsArray == rkl_cachedRegexCacheSets) ? cacheSet < _RKL_REGEX_LRU_CACHE_SETS : 1));
  cacheSetsArray[cacheSet] = (RKLLRUCacheSet_t)(((cacheSetsArray[cacheSet] & (RKLLRUCacheSet_t)0xFFFFU) | (((RKLLRUCacheSet_t)0xFU) << (cacheWay * 4U))) & (~(((RKLLRUCacheSet_t)0x1111U) << (3U - cacheWay))));
}

#pragma mark Common, macro'ish compiled regular expression cache logic

// These functions consolidate bits and pieces of code used to maintain, update, and access the 4-way set associative LRU cache and Regex Lookaside Cache.
RKL_STATIC_INLINE NSUInteger      rkl_regexLookasideCacheIndexForPointerAndOptions  (const void           *ptr,       RKLRegexOptions options)                       { return(((((NSUInteger)(ptr)) >> 4) + options + (options >> 4)) & _RKL_REGEX_LOOKASIDE_CACHE_MASK); }
RKL_STATIC_INLINE void            rkl_setRegexLookasideCacheToCachedRegexForPointer (const RKLCachedRegex *cachedRegex, const void *ptr)                             { rkl_regexLookasideCache[rkl_regexLookasideCacheIndexForPointerAndOptions(ptr, cachedRegex->options)] = (cachedRegex - rkl_cachedRegexes); }
RKL_STATIC_INLINE RKLCachedRegex *rkl_cachedRegexFromRegexLookasideCacheForString   (const void           *ptr,       RKLRegexOptions options)                       { return(&rkl_cachedRegexes[rkl_regexLookasideCache[rkl_regexLookasideCacheIndexForPointerAndOptions(ptr, options)]]); }
RKL_STATIC_INLINE NSUInteger      rkl_makeCacheSetHash                              (      CFHashCode      regexHash, RKLRegexOptions options)                       { return((NSUInteger)regexHash ^ (NSUInteger)options); }
RKL_STATIC_INLINE NSUInteger      rkl_cacheSetForRegexHashAndOptions                (      CFHashCode      regexHash, RKLRegexOptions options)                       { return((rkl_makeCacheSetHash(regexHash, options) % _RKL_REGEX_LRU_CACHE_SETS)); }
RKL_STATIC_INLINE NSUInteger      rkl_cacheWayForCachedRegex                        (const RKLCachedRegex *cachedRegex)                                              { return((cachedRegex - rkl_cachedRegexes) % _RKL_LRU_CACHE_SET_WAYS); }
RKL_STATIC_INLINE NSUInteger      rkl_cacheSetForCachedRegex                        (const RKLCachedRegex *cachedRegex)                                              { return(rkl_cacheSetForRegexHashAndOptions(cachedRegex->regexHash, cachedRegex->options)); }
RKL_STATIC_INLINE RKLCachedRegex *rkl_cachedRegexForCacheSetAndWay                  (      NSUInteger      cacheSet,  NSUInteger cacheWay)                           { return(&rkl_cachedRegexes[((cacheSet * _RKL_LRU_CACHE_SET_WAYS) + cacheWay)]); }
RKL_STATIC_INLINE RKLCachedRegex *rkl_cachedRegexForRegexHashAndOptionsAndWay       (      CFHashCode      regexHash, RKLRegexOptions options, NSUInteger cacheWay)  { return(rkl_cachedRegexForCacheSetAndWay(rkl_cacheSetForRegexHashAndOptions(regexHash, options), cacheWay)); }

RKL_STATIC_INLINE void rkl_updateCachesWithCachedRegex(RKLCachedRegex *cachedRegex, const void *ptr, int hitOrMiss RKL_UNUSED_DTRACE_ARG, int status RKL_UNUSED_DTRACE_ARG) {
  rkl_lastCachedRegex = cachedRegex;
  rkl_setRegexLookasideCacheToCachedRegexForPointer(cachedRegex, ptr);
  rkl_accessCacheSetWay(_RKL_REGEX_LRU_CACHE_SETS, rkl_cachedRegexCacheSets, rkl_cacheSetForCachedRegex(cachedRegex), rkl_cacheWayForCachedRegex(cachedRegex)); // Set the matching line as the most recently used.
  rkl_dtrace_compiledRegexCache(&rkl_dtrace_regexUTF8[(cachedRegex - rkl_cachedRegexes)][0], cachedRegex->options, (int)cachedRegex->captureCount, hitOrMiss, status, NULL);
}

RKL_STATIC_INLINE RKLCachedRegex *rkl_leastRecentlyUsedCachedRegexForRegexHashAndOptions(CFHashCode regexHash, RKLRegexOptions options) {
  NSUInteger cacheSet = rkl_cacheSetForRegexHashAndOptions(regexHash, options);
  return(rkl_cachedRegexForCacheSetAndWay(cacheSet, rkl_leastRecentlyUsedWayInSet(_RKL_REGEX_LRU_CACHE_SETS, rkl_cachedRegexCacheSets, cacheSet)));
}

#pragma mark Regular expression lookup function

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called with rkl_cacheSpinLock already locked!
//  ----------

static RKLCachedRegex *rkl_getCachedRegex(NSString *regexString, RKLRegexOptions options, NSError **error, id *exception) {
  //  ----------   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  //  IMPORTANT!   This section of code is called almost every single time that any RegexKitLite functionality is used! It /MUST/ be very fast!
  //  ----------   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  
  RKLCachedRegex *cachedRegex = NULL;
  CFHashCode      regexHash   = 0UL;
  int32_t         status      = 0;

  RKLCDelayedAssert((rkl_cacheSpinLock != (OSSpinLock)0) && (regexString != NULL), exception, exitNow);
  
  // Fast path the common case where this regex is exactly the same one used last time.
  // The pointer equality test is valid under these circumstances since the cachedRegex->regexString is an immutable copy.
  // If the regexString argument is mutable, this test will fail, and we'll use the the slow path cache check below.
  if(RKL_EXPECTED(rkl_lastCachedRegex != NULL, 1L) && RKL_EXPECTED(rkl_lastCachedRegex->regexString == (CFStringRef)regexString, 1L) && RKL_EXPECTED(rkl_lastCachedRegex->options == options, 1L) && RKL_EXPECTED(rkl_lastCachedRegex->icu_regex != NULL, 1L)) {
    rkl_dtrace_compiledRegexCache(&rkl_dtrace_regexUTF8[(rkl_lastCachedRegex - rkl_cachedRegexes)][0], rkl_lastCachedRegex->options, (int)rkl_lastCachedRegex->captureCount, 1, 0, NULL);
    return(rkl_lastCachedRegex);
  }

  rkl_lastCachedRegex = NULL; // Make sure that rkl_lastCachedRegex is NULL in case there is some kind of error.
  cachedRegex         = rkl_cachedRegexFromRegexLookasideCacheForString(regexString, options); // Check the Regex Lookaside Cache to see if we can quickly find the correct Cached Regex for this regexString pointer + options.
  if((RKL_EXPECTED(cachedRegex->regexString == (CFStringRef)regexString, 1L) || (RKL_EXPECTED(cachedRegex->regexString != NULL, 1L) && RKL_EXPECTED(CFEqual((CFTypeRef)regexString, (CFTypeRef)cachedRegex->regexString) == YES, 1L))) && RKL_EXPECTED(cachedRegex->options == options, 1L) && RKL_EXPECTED(cachedRegex->icu_regex != NULL, 1L)) { goto foundMatch; } // There was a Regex Lookaside Cache hit, jump to foundMatch: to quickly return the result. A Regex Lookaside Cache hit allows us to bypass calling CFHash(), which is a decent performance win.
  else { cachedRegex = NULL; regexHash = CFHash((CFTypeRef)regexString); } // Regex Lookaside Cache miss.  We need to call CFHash() to determine the cache set for this regex.

  NSInteger cacheWay = 0L;                                                               // Check each way of the set that this regex belongs to.
  for(cacheWay = ((NSInteger)_RKL_LRU_CACHE_SET_WAYS - 1L); cacheWay > 0L; cacheWay--) { // Checking the ways in reverse (3, 2, 1, 0) finds a match "sooner" on average.
    cachedRegex = rkl_cachedRegexForRegexHashAndOptionsAndWay(regexHash, options, (NSUInteger)cacheWay);
    // Return the cached entry if it's a match. If regexString is mutable, the pointer equality test will fail, and CFEqual() is used to determine true equality with the immutable cachedRegex copy.  CFEqual() performs a slow character by character check.
    if(RKL_EXPECTED(cachedRegex->regexHash == regexHash, 0UL) && ((cachedRegex->regexString == (CFStringRef)regexString) || (RKL_EXPECTED(cachedRegex->regexString != NULL, 1L) && RKL_EXPECTED(CFEqual((CFTypeRef)regexString, (CFTypeRef)cachedRegex->regexString) == YES, 1L))) && RKL_EXPECTED(cachedRegex->options == options, 1L) && RKL_EXPECTED(cachedRegex->icu_regex != NULL, 1L)) {
    foundMatch: // Control can transfer here (from above) via a Regex Lookaside Cache hit.
      rkl_updateCachesWithCachedRegex(cachedRegex, regexString, 1, 0);
      return(cachedRegex);
    }
  }

  //  ----------   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //  IMPORTANT!   This section of code is called almost every single time that any RegexKitLite functionality is used! It /MUST/ be very fast!
  //  ----------   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

  // Code below this point is not as sensitive to speed since compiling a regular expression is an extremely expensive operation.
  // The regex was not found in the cache.  Get the cached regex for the least recently used line in the set, then clear the cached regex and create a new ICU regex in its place.
  cachedRegex = rkl_leastRecentlyUsedCachedRegexForRegexHashAndOptions(regexHash, options);
  rkl_clearCachedRegex(cachedRegex);
  
  if(RKL_EXPECTED((cachedRegex->regexString = CFStringCreateCopy(NULL, (CFStringRef)regexString)) == NULL, 0L)) { goto exitNow; } ; // Get a cheap immutable copy.
  rkl_dtrace_getRegexUTF8(cachedRegex->regexString, &rkl_dtrace_regexUTF8[(cachedRegex - rkl_cachedRegexes)][0]);
  cachedRegex->regexHash = regexHash;
  cachedRegex->options   = options;
  
  CFIndex                                        regexStringU16Length = CFStringGetLength(cachedRegex->regexString); // In UTF16 code units.
  UParseError                                    parseError           = (UParseError){-1, -1, {0}, {0}};
  RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE regexUniChar         = NULL;
  
  if(RKL_EXPECTED(regexStringU16Length >= (CFIndex)INT_MAX, 0L)) { *exception = [NSException exceptionWithName:NSRangeException reason:@"Regex string length exceeds INT_MAX" userInfo:NULL]; goto exitNow; }

  // Try to quickly obtain regexString in UTF16 format.
  if((regexUniChar = CFStringGetCharactersPtr(cachedRegex->regexString)) == NULL) { // We didn't get the UTF16 pointer quickly and need to perform a full conversion in a temp buffer.
    RKL_STRONG_REF UniChar * RKL_GC_VOLATILE uniCharBuffer = NULL;
    if(((size_t)regexStringU16Length * sizeof(UniChar)) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((uniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)alloca(                            (size_t)regexStringU16Length * sizeof(UniChar)     )) == NULL, 0L)) { goto exitNow; } } // Try to use the stack.
    else {                                                                            if(RKL_EXPECTED((uniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_realloc(&rkl_scratchBuffer[0], (size_t)regexStringU16Length * sizeof(UniChar), 0UL)) == NULL, 0L)) { goto exitNow; } } // Otherwise use the heap.
    CFStringGetCharacters(cachedRegex->regexString, CFMakeRange(0L, regexStringU16Length), uniCharBuffer); // Convert regexString to UTF16.
    regexUniChar = uniCharBuffer;
  }
  
  // Create the ICU regex.
  if(RKL_EXPECTED((cachedRegex->icu_regex = RKL_ICU_FUNCTION_APPEND(uregex_open)(regexUniChar, (int32_t)regexStringU16Length, options, &parseError, &status)) == NULL, 0L)) { goto exitNow; }
  if(RKL_EXPECTED(status <= U_ZERO_ERROR, 1L)) { cachedRegex->captureCount = (NSInteger)RKL_ICU_FUNCTION_APPEND(uregex_groupCount)(cachedRegex->icu_regex, &status); }
  if(RKL_EXPECTED(status <= U_ZERO_ERROR, 1L)) { rkl_updateCachesWithCachedRegex(cachedRegex, regexString, 0, status); }
  
exitNow:
  if(RKL_EXPECTED(rkl_scratchBuffer[0] != NULL,         0L)) { rkl_scratchBuffer[0] = rkl_free(&rkl_scratchBuffer[0]); }
  if(RKL_EXPECTED(status                > U_ZERO_ERROR, 0L)) { rkl_clearCachedRegex(cachedRegex); cachedRegex = rkl_lastCachedRegex = NULL; if(error != NULL) { *error = rkl_makeNSError((RKLUserInfoOptions)RKLUserInfoNone, regexString, options, &parseError, status, NULL, NSNotFoundRange, NULL, NULL, 0L, (RKLRegexEnumerationOptions)RKLRegexEnumerationNoOptions, @"There was an error compiling the regular expression."); } }
  
#ifdef    _RKL_DTRACE_ENABLED
  if(RKL_EXPECTED(cachedRegex == NULL, 1L)) { char regexUTF8[_RKL_DTRACE_REGEXUTF8_SIZE]; const char *err = NULL; if(status != U_ZERO_ERROR) { err = RKL_ICU_FUNCTION_APPEND(u_errorName)(status); } rkl_dtrace_getRegexUTF8((CFStringRef)regexString, regexUTF8); rkl_dtrace_compiledRegexCache(regexUTF8, options, -1, -1, status, err); }
#endif // _RKL_DTRACE_ENABLED
  
  return(cachedRegex);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called with rkl_cacheSpinLock already locked!
//  ----------

#pragma mark Set a cached regular expression to a NSStrings UTF-16 text

static NSUInteger rkl_setCachedRegexToString(RKLCachedRegex *cachedRegex, const NSRange *range, int32_t *status, id *exception RKL_UNUSED_ASSERTION_ARG) {
  //  ----------   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  //  IMPORTANT!   This section of code is called almost every single time that any RegexKitLite functionality is used! It /MUST/ be very fast!
  //  ----------   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  
  RKLCDelayedAssert((cachedRegex != NULL) && (cachedRegex->setToString != NULL) && ((range != NULL) && (NSEqualRanges(*range, NSNotFoundRange) == NO)) && (status != NULL), exception, exitNow);
  RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE stringUniChar = NULL;
#ifdef _RKL_DTRACE_ENABLED
  unsigned int lookupResultFlags = 0U;
#endif
  
  NSUInteger  useFixedBuffer = (cachedRegex->setToLength < (CFIndex)_RKL_FIXED_LENGTH) ? 1UL : 0UL;
  RKLBuffer  *buffer         = NULL;
  
  if(cachedRegex->setToNeedsConversion == 0U) {
    RKLCDelayedAssert((cachedRegex->setToUniChar != NULL) && (cachedRegex->buffer == NULL), exception, exitNow);
    if(RKL_EXPECTED((stringUniChar = (RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE)CFStringGetCharactersPtr(cachedRegex->setToString)) == NULL, 0L)) { cachedRegex->setToUniChar = NULL; cachedRegex->setToRange = NSNotFoundRange; cachedRegex->setToNeedsConversion = 1U; }
    else { if(RKL_EXPECTED(cachedRegex->setToUniChar != stringUniChar, 0L)) { cachedRegex->setToRange = NSNotFoundRange; cachedRegex->setToUniChar = stringUniChar; } goto setRegexText; }
  }

  buffer = cachedRegex->buffer;

  RKLCDelayedAssert((buffer == NULL) ? 1 : (((buffer == &rkl_lruFixedBuffer[0])   || (buffer == &rkl_lruFixedBuffer[1])   || (buffer == &rkl_lruFixedBuffer[2])   || (buffer == &rkl_lruFixedBuffer[3])) ||
                                            ((buffer == &rkl_lruDynamicBuffer[0]) || (buffer == &rkl_lruDynamicBuffer[1]) || (buffer == &rkl_lruDynamicBuffer[2]) || (buffer == &rkl_lruDynamicBuffer[3]))), exception, exitNow);
  
  if((buffer != NULL) && RKL_EXPECTED(cachedRegex->setToString == buffer->string, 1L) && RKL_EXPECTED(cachedRegex->setToHash == buffer->hash, 1L) && RKL_EXPECTED(cachedRegex->setToLength == buffer->length, 1L)) {
    RKLCDelayedAssert((buffer->uniChar != NULL), exception, exitNow);
    rkl_dtrace_addLookupFlag(lookupResultFlags, RKLCacheHitLookupFlag | RKLConversionRequiredLookupFlag | (useFixedBuffer ? 0U : RKLDynamicBufferLookupFlag));
    if(cachedRegex->setToUniChar != buffer->uniChar) { cachedRegex->setToRange = NSNotFoundRange; cachedRegex->setToUniChar = buffer->uniChar; }
    goto setRegexText;
  }

  buffer              = NULL;
  cachedRegex->buffer = NULL;

  NSInteger cacheWay = 0L;
  for(cacheWay = ((NSInteger)_RKL_LRU_CACHE_SET_WAYS - 1L); cacheWay > 0L; cacheWay--) {
    if(useFixedBuffer) { buffer = &rkl_lruFixedBuffer[cacheWay]; } else { buffer = &rkl_lruDynamicBuffer[cacheWay]; }
    if(RKL_EXPECTED(cachedRegex->setToString == buffer->string, 1L) && RKL_EXPECTED(cachedRegex->setToHash == buffer->hash, 1L) && RKL_EXPECTED(cachedRegex->setToLength == buffer->length, 1L)) {
      RKLCDelayedAssert((buffer->uniChar != NULL), exception, exitNow);
      rkl_dtrace_addLookupFlag(lookupResultFlags, RKLCacheHitLookupFlag | RKLConversionRequiredLookupFlag | (useFixedBuffer ? 0U : RKLDynamicBufferLookupFlag));
      if(cachedRegex->setToUniChar != buffer->uniChar) { cachedRegex->setToRange = NSNotFoundRange; cachedRegex->setToUniChar = buffer->uniChar; }
      cachedRegex->buffer = buffer;
      goto setRegexText;
    }
  }

  buffer                    = NULL;
  cachedRegex->setToUniChar = NULL;
  cachedRegex->setToRange   = NSNotFoundRange;
  cachedRegex->buffer       = NULL;
  
  RKLCDelayedAssert((cachedRegex->setToNeedsConversion == 1U) && (cachedRegex->buffer == NULL), exception, exitNow);
  if(RKL_EXPECTED(cachedRegex->setToNeedsConversion == 1U, 1L) && RKL_EXPECTED((cachedRegex->setToUniChar = (RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE)CFStringGetCharactersPtr(cachedRegex->setToString)) != NULL, 0L)) { cachedRegex->setToNeedsConversion = 0U; cachedRegex->setToRange = NSNotFoundRange; goto setRegexText; }
  
  rkl_dtrace_addLookupFlag(lookupResultFlags, RKLConversionRequiredLookupFlag | (useFixedBuffer ? 0U : RKLDynamicBufferLookupFlag));

  if(useFixedBuffer) { buffer = &rkl_lruFixedBuffer  [rkl_leastRecentlyUsedWayInSet(1UL, &rkl_lruFixedBufferCacheSet,   0UL)]; }
  else               { buffer = &rkl_lruDynamicBuffer[rkl_leastRecentlyUsedWayInSet(1UL, &rkl_lruDynamicBufferCacheSet, 0UL)]; }

  RKLCDelayedAssert((useFixedBuffer) ? ((buffer == &rkl_lruFixedBuffer[0])   || (buffer == &rkl_lruFixedBuffer[1])   || (buffer == &rkl_lruFixedBuffer[2])   || (buffer == &rkl_lruFixedBuffer[3])) :
                                       ((buffer == &rkl_lruDynamicBuffer[0]) || (buffer == &rkl_lruDynamicBuffer[1]) || (buffer == &rkl_lruDynamicBuffer[2]) || (buffer == &rkl_lruDynamicBuffer[3])), exception, exitNow);
  
  rkl_clearBuffer(buffer, 0UL);

  RKLCDelayedAssert((buffer->string == NULL) && (cachedRegex->setToString != NULL), exception, exitNow);
  if(RKL_EXPECTED((buffer->string = (CFStringRef)CFRetain((CFTypeRef)cachedRegex->setToString)) == NULL, 0L)) { goto exitNow; }
  buffer->hash   = cachedRegex->setToHash;
  buffer->length = cachedRegex->setToLength;
  
  if(useFixedBuffer == 0UL) {
    RKL_STRONG_REF void * RKL_GC_VOLATILE p = (RKL_STRONG_REF void * RKL_GC_VOLATILE)buffer->uniChar;
    if(RKL_EXPECTED((buffer->uniChar = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_realloc(&p, ((size_t)buffer->length * sizeof(UniChar)), 0UL)) == NULL, 0L)) { goto exitNow; } // Resize the buffer.
  }
  
  RKLCDelayedAssert((buffer->string != NULL) && (buffer->uniChar != NULL), exception, exitNow);
  CFStringGetCharacters(buffer->string, CFMakeRange(0L, buffer->length), (UniChar *)buffer->uniChar); // Convert to a UTF16 string.
  
  cachedRegex->setToUniChar = buffer->uniChar;
  cachedRegex->setToRange   = NSNotFoundRange;
  cachedRegex->buffer       = buffer;

setRegexText:
  if(buffer != NULL) { if(useFixedBuffer == 1UL) { rkl_accessCacheSetWay(1UL, &rkl_lruFixedBufferCacheSet, 0UL, (NSUInteger)(buffer - rkl_lruFixedBuffer)); } else { rkl_accessCacheSetWay(1UL, &rkl_lruDynamicBufferCacheSet, 0UL, (NSUInteger)(buffer - rkl_lruDynamicBuffer)); } }

  if(NSEqualRanges(cachedRegex->setToRange, *range) == NO) {
    RKLCDelayedAssert((cachedRegex->icu_regex != NULL) && (cachedRegex->setToUniChar != NULL) && (NSMaxRange(*range) <= (NSUInteger)cachedRegex->setToLength) && (cachedRegex->setToRange.length <= INT_MAX), exception, exitNow);
    cachedRegex->lastFindRange =  cachedRegex->lastMatchRange = NSNotFoundRange;
    cachedRegex->setToRange    = *range;
    RKL_ICU_FUNCTION_APPEND(uregex_setText)(cachedRegex->icu_regex, cachedRegex->setToUniChar + cachedRegex->setToRange.location, (int32_t)cachedRegex->setToRange.length, status);
    rkl_dtrace_addLookupFlag(lookupResultFlags, RKLSetTextLookupFlag);
    if(RKL_EXPECTED(*status > U_ZERO_ERROR, 0L)) { rkl_dtrace_addLookupFlag(lookupResultFlags, RKLErrorLookupFlag); goto exitNow; }
  }
  
  rkl_dtrace_utf16ConversionCache(lookupResultFlags, cachedRegex->setToString, cachedRegex->setToRange.location, cachedRegex->setToRange.length, cachedRegex->setToLength);

  return(1UL);

  //  ----------   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //  IMPORTANT!   This section of code is called almost every single time that any RegexKitLite functionality is used! It /MUST/ be very fast!
  //  ----------   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  
exitNow:
#ifdef    _RKL_DTRACE_ENABLED
  rkl_dtrace_addLookupFlag(lookupResultFlags, RKLErrorLookupFlag); 
  if(cachedRegex != NULL) { rkl_dtrace_utf16ConversionCache(lookupResultFlags, cachedRegex->setToString, cachedRegex->setToRange.location, cachedRegex->setToRange.length, cachedRegex->setToLength); }
#endif // _RKL_DTRACE_ENABLED
  if(cachedRegex != NULL) { cachedRegex->buffer = NULL; cachedRegex->setToRange = NSNotFoundRange; cachedRegex->lastFindRange = NSNotFoundRange; cachedRegex->lastMatchRange = NSNotFoundRange; }
  return(0UL);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called with rkl_cacheSpinLock already locked!
//  ----------

#pragma mark Get a regular expression and set it to a NSStrings UTF-16 text

static RKLCachedRegex *rkl_getCachedRegexSetToString(NSString *regexString, RKLRegexOptions options, NSString *matchString, NSUInteger *matchLengthPtr, NSRange *matchRange, NSError **error, id *exception, int32_t *status) {
  //  ----------   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  //  IMPORTANT!   This section of code is called almost every single time that any RegexKitLite functionality is used! It /MUST/ be very fast!
  //  ----------   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  
  RKLCachedRegex *cachedRegex = NULL;
  RKLCDelayedAssert((regexString != NULL) && (matchString != NULL) && (exception != NULL) && (status != NULL) && (matchLengthPtr != NULL), exception, exitNow);

  if(RKL_EXPECTED((cachedRegex = rkl_getCachedRegex(regexString, options, error, exception)) == NULL, 0L)) { goto exitNow; }
  RKLCDelayedAssert(((cachedRegex >= rkl_cachedRegexes) && ((cachedRegex - rkl_cachedRegexes) < (ssize_t)_RKL_REGEX_CACHE_LINES)) && (cachedRegex != NULL) && (cachedRegex->icu_regex != NULL) && (cachedRegex->regexString != NULL) && (cachedRegex->captureCount >= 0L) && (cachedRegex == rkl_lastCachedRegex), exception, exitNow);

  // Optimize the case where the string to search (matchString) is immutable and the setToString immutable copy is the same string with its reference count incremented.
  NSUInteger isSetTo     = ((cachedRegex->setToString      == (CFStringRef)matchString)) ? 1UL : 0UL;
  CFIndex    matchLength = ((cachedRegex->setToIsImmutable == 1U) && (isSetTo == 1UL))   ? cachedRegex->setToLength : CFStringGetLength((CFStringRef)matchString);

  *matchLengthPtr = (NSUInteger)matchLength;
  if(matchRange->length == NSUIntegerMax) { matchRange->length = (NSUInteger)matchLength; } // For convenience, allow NSUIntegerMax == string length.
  
  if(RKL_EXPECTED((NSUInteger)matchLength < NSMaxRange(*matchRange), 0L)) { goto exitNow; } // The match range is out of bounds for the string.  performRegexOp will catch and report the problem.

  RKLCDelayedAssert((isSetTo == 1UL) ? (cachedRegex->setToString != NULL) : 1, exception, exitNow);

  if(((cachedRegex->setToIsImmutable == 1U) ? isSetTo : (NSUInteger)((isSetTo == 1UL) && (cachedRegex->setToLength == matchLength) && (cachedRegex->setToHash == CFHash((CFTypeRef)matchString)))) == 0UL) {
    if(cachedRegex->setToString != NULL) { rkl_clearCachedRegexSetTo(cachedRegex); }
    
    cachedRegex->setToString          = (CFStringRef)CFRetain((CFTypeRef)matchString);
    RKLCDelayedAssert(cachedRegex->setToString != NULL, exception, exitNow);
    cachedRegex->setToUniChar         = CFStringGetCharactersPtr(cachedRegex->setToString);
    cachedRegex->setToNeedsConversion = (cachedRegex->setToUniChar == NULL) ? 1U : 0U;
    cachedRegex->setToIsImmutable     = (rkl_CFStringIsMutable(cachedRegex->setToString) == YES) ? 0U : 1U; // If RKL_FAST_MUTABLE_CHECK is not defined then setToIsImmutable will always be set to '0', or in other words mutable..
    cachedRegex->setToHash            = CFHash((CFTypeRef)cachedRegex->setToString);
    cachedRegex->setToRange           = NSNotFoundRange;
    cachedRegex->setToLength          = matchLength;
    
  }
  
  if(RKL_EXPECTED(rkl_setCachedRegexToString(cachedRegex, matchRange, status, exception) == 0UL, 0L)) { cachedRegex = NULL; if(*exception == NULL) { *exception = (id)RKLCAssertDictionary(@"Failed to set up UTF16 buffer."); } goto exitNow; }
  
exitNow:
  return(cachedRegex);
  //  ----------   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //  IMPORTANT!   This section of code is called almost every single time that any RegexKitLite functionality is used! It /MUST/ be very fast!
  //  ----------   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
}

#pragma mark GCC cleanup __attribute__ functions that ensure the global rkl_cacheSpinLock is properly unlocked
#ifdef    RKL_HAVE_CLEANUP

// rkl_cleanup_cacheSpinLockStatus takes advantage of GCC's 'cleanup' variable attribute.  When an 'auto' variable with the 'cleanup' attribute goes out of scope,
// GCC arranges to have the designated function called.  In this case, we make sure that if rkl_cacheSpinLock was locked that it was also unlocked.
// If rkl_cacheSpinLock was locked, but the rkl_cacheSpinLockStatus unlocked flag was not set, we force rkl_cacheSpinLock unlocked with a call to OSSpinLockUnlock.
// This is not a panacea for preventing mutex usage errors.  Old style ObjC exceptions will bypass the cleanup call, but newer C++ style ObjC exceptions should cause the cleanup function to be called during the stack unwind.

// We do not depend on this cleanup function being called.  It is used only as an extra safety net.  It is probably a bug in RegexKitLite if it is ever invoked and forced to take some kind of protective action.

volatile NSUInteger rkl_debugCacheSpinLockCount = 0UL;

void        rkl_debugCacheSpinLock          (void)                                            RKL_ATTRIBUTES(used, noinline, visibility("default"));
static void rkl_cleanup_cacheSpinLockStatus (volatile NSUInteger *rkl_cacheSpinLockStatusPtr) RKL_ATTRIBUTES(used);

void rkl_debugCacheSpinLock(void) {
  rkl_debugCacheSpinLockCount++; // This is here primarily to prevent the optimizer from optimizing away the function.
}

static void rkl_cleanup_cacheSpinLockStatus(volatile NSUInteger *rkl_cacheSpinLockStatusPtr) {
  static NSUInteger didPrintForcedUnlockWarning = 0UL, didPrintNotLockedWarning = 0UL;
  NSUInteger        rkl_cacheSpinLockStatus     = *rkl_cacheSpinLockStatusPtr;
  
  if(RKL_EXPECTED((rkl_cacheSpinLockStatus & RKLUnlockedCacheSpinLock) == 0UL, 0L) && RKL_EXPECTED((rkl_cacheSpinLockStatus & RKLLockedCacheSpinLock) != 0UL, 1L)) {
    if(rkl_cacheSpinLock != (OSSpinLock)0) {
      if(didPrintForcedUnlockWarning == 0UL) { didPrintForcedUnlockWarning = 1UL; NSLog(@"[RegexKitLite] Unusual condition detected: Recorded that rkl_cacheSpinLock was locked, but for some reason it was not unlocked.  Forcibly unlocking rkl_cacheSpinLock. Set a breakpoint at rkl_debugCacheSpinLock to debug. This warning is only printed once."); }
      rkl_debugCacheSpinLock(); // Since this is an unusual condition, offer an attempt to catch it before we unlock.
      OSSpinLockUnlock(&rkl_cacheSpinLock);
    } else {
      if(didPrintNotLockedWarning    == 0UL) { didPrintNotLockedWarning    = 1UL; NSLog(@"[RegexKitLite] Unusual condition detected: Recorded that rkl_cacheSpinLock was locked, but for some reason it was not unlocked, yet rkl_cacheSpinLock is currently not locked? Set a breakpoint at rkl_debugCacheSpinLock to debug. This warning is only printed once."); }
      rkl_debugCacheSpinLock();
    }
  }
}

#endif // RKL_HAVE_CLEANUP

// rkl_performDictionaryVarArgsOp is a front end to rkl_performRegexOp which converts a ', ...' varargs key/captures list and converts it in to a form that rkl_performRegexOp can use.
// All error checking of arguments is handled by rkl_performRegexOp.

#pragma mark Front end function that handles varargs and calls rkl_performRegexOp with the marshaled results

static id rkl_performDictionaryVarArgsOp(id self, SEL _cmd, RKLRegexOp regexOp, NSString *regexString, RKLRegexOptions options, NSInteger capture, id matchString, NSRange *matchRange, NSString *replacementString, NSError **error, void *result, id firstKey, va_list varArgsList) {
  id         captureKeys[64];
  int        captureKeyIndexes[64];
  NSUInteger captureKeysCount = 0UL;
  
  if(varArgsList != NULL) {
    while(captureKeysCount < 62UL) {
      id  thisCaptureKey      = (captureKeysCount == 0) ? firstKey : va_arg(varArgsList, id);
      if(RKL_EXPECTED(thisCaptureKey == NULL, 0L)) { break; }
      int thisCaptureKeyIndex = va_arg(varArgsList, int);
      captureKeys[captureKeysCount]       = thisCaptureKey;
      captureKeyIndexes[captureKeysCount] = thisCaptureKeyIndex;
      captureKeysCount++;
    }
  }
  
  return(rkl_performRegexOp(self, _cmd, regexOp, regexString, options, capture, matchString, matchRange, replacementString, error, result, captureKeysCount, captureKeys, captureKeyIndexes));
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  ----------

#pragma mark Primary internal function that Objective-C methods call to perform regular expression operations

static id rkl_performRegexOp(id self, SEL _cmd, RKLRegexOp regexOp, NSString *regexString, RKLRegexOptions options, NSInteger capture, id matchString, NSRange *matchRange, NSString *replacementString, NSError **error, void *result, NSUInteger captureKeysCount, id captureKeys[captureKeysCount], const int captureKeyIndexes[captureKeysCount]) {
  volatile NSUInteger RKL_CLEANUP(rkl_cleanup_cacheSpinLockStatus) rkl_cacheSpinLockStatus = 0UL;
  
  NSUInteger replaceMutable = 0UL;
  RKLRegexOp maskedRegexOp  = (regexOp & RKLMaskOp);
  BOOL       dictionaryOp   = ((maskedRegexOp == RKLDictionaryOfCapturesOp) || (maskedRegexOp == RKLArrayOfDictionariesOfCapturesOp)) ? YES : NO;
  
  if((error != NULL) && (*error != NULL))                                            { *error = NULL; }
  
  if(RKL_EXPECTED(regexString == NULL, 0L))                                          { RKL_RAISE_EXCEPTION(NSInvalidArgumentException, @"The regular expression argument is NULL."); }
  if(RKL_EXPECTED(matchString == NULL, 0L))                                          { RKL_RAISE_EXCEPTION(NSInternalInconsistencyException, @"The match string argument is NULL."); }
  if(RKL_EXPECTED(matchRange  == NULL, 0L))                                          { RKL_RAISE_EXCEPTION(NSInternalInconsistencyException, @"The match range argument is NULL.");  }
  if((maskedRegexOp == RKLReplaceOp) && RKL_EXPECTED(replacementString == NULL, 0L)) { RKL_RAISE_EXCEPTION(NSInvalidArgumentException, @"The replacement string argument is NULL."); }
  if((dictionaryOp  == YES)          && RKL_EXPECTED(captureKeys       == NULL, 0L)) { RKL_RAISE_EXCEPTION(NSInvalidArgumentException, @"The keys argument is NULL.");               }
  if((dictionaryOp  == YES)          && RKL_EXPECTED(captureKeyIndexes == NULL, 0L)) { RKL_RAISE_EXCEPTION(NSInvalidArgumentException, @"The captures argument is NULL.");           }
  
  id              resultObject    = NULL, exception = NULL;
  int32_t         status          = U_ZERO_ERROR;
  RKLCachedRegex *cachedRegex     = NULL;
  NSUInteger      stringU16Length = 0UL, tmpIdx = 0UL;
  NSRange         stackRanges[2048];
  RKLFindAll      findAll;
  
  // IMPORTANT!   Once we have obtained the lock, code MUST exit via 'goto exitNow;' to unlock the lock!  NO EXCEPTIONS!
  // ----------
  OSSpinLockLock(&rkl_cacheSpinLock); // Grab the lock and get cache entry.
  rkl_cacheSpinLockStatus |= RKLLockedCacheSpinLock;
  rkl_dtrace_incrementEventID();
  
  if(RKL_EXPECTED((cachedRegex = rkl_getCachedRegexSetToString(regexString, options, matchString, &stringU16Length, matchRange, error, &exception, &status)) == NULL, 0L)) { stringU16Length = (NSUInteger)CFStringGetLength((CFStringRef)matchString); }
  if(RKL_EXPECTED(matchRange->length == NSUIntegerMax,           0L))                                        { matchRange->length = stringU16Length; } // For convenience.
  if(RKL_EXPECTED(stringU16Length     < NSMaxRange(*matchRange), 0L) && RKL_EXPECTED(exception == NULL, 1L)) { exception = (id)RKL_EXCEPTION(NSRangeException, @"Range or index out of bounds.");  goto exitNow; }
  if(RKL_EXPECTED(stringU16Length    >= (NSUInteger)INT_MAX,     0L) && RKL_EXPECTED(exception == NULL, 1L)) { exception = (id)RKL_EXCEPTION(NSRangeException, @"String length exceeds INT_MAX."); goto exitNow; }
  if(((maskedRegexOp == RKLRangeOp) || (maskedRegexOp == RKLArrayOfStringsOp)) && RKL_EXPECTED(cachedRegex != NULL, 1L) && (RKL_EXPECTED(capture < 0L, 0L) || RKL_EXPECTED(capture > cachedRegex->captureCount, 0L)) && RKL_EXPECTED(exception == NULL, 1L)) { exception = (id)RKL_EXCEPTION(NSInvalidArgumentException, @"The capture argument is not valid."); goto exitNow; }

  if((dictionaryOp == YES) && RKL_EXPECTED(cachedRegex != NULL, 1L) && RKL_EXPECTED(exception == NULL, 1L)) {
    for(tmpIdx = 0UL; tmpIdx < captureKeysCount; tmpIdx++) {
      if(RKL_EXPECTED(captureKeys[tmpIdx] == NULL, 0L)) { exception = (id)RKL_EXCEPTION(NSInvalidArgumentException, @"The capture key (key %lu of %lu) is NULL.", (unsigned long)(tmpIdx + 1UL), (unsigned long)captureKeysCount); break; }
      if((RKL_EXPECTED(captureKeyIndexes[tmpIdx] < 0, 0L) || RKL_EXPECTED(captureKeyIndexes[tmpIdx] > cachedRegex->captureCount, 0L))) { exception = (id)RKL_EXCEPTION(NSInvalidArgumentException, @"The capture argument %d (capture %lu of %lu) for key '%@' is not valid.", captureKeyIndexes[tmpIdx], (unsigned long)(tmpIdx + 1UL), (unsigned long)captureKeysCount, captureKeys[tmpIdx]); break; }
    }
  }

  if(RKL_EXPECTED(cachedRegex == NULL, 0L) || RKL_EXPECTED(status > U_ZERO_ERROR, 0L) || RKL_EXPECTED(exception != NULL, 0L)) { goto exitNow; }
  
  RKLCDelayedAssert(((cachedRegex >= rkl_cachedRegexes) && ((cachedRegex - rkl_cachedRegexes) < (ssize_t)_RKL_REGEX_CACHE_LINES)) && (cachedRegex != NULL) && (cachedRegex->icu_regex != NULL) && (cachedRegex->regexString != NULL) && (cachedRegex->captureCount >= 0L) && (cachedRegex->setToString != NULL) && (cachedRegex->setToLength >= 0L) && (cachedRegex->setToUniChar != NULL) && ((CFIndex)NSMaxRange(cachedRegex->setToRange) <= cachedRegex->setToLength), &exception, exitNow);
  RKLCDelayedAssert((cachedRegex->setToNeedsConversion == 0U) ? ((cachedRegex->setToNeedsConversion == 0U) && (cachedRegex->setToUniChar == CFStringGetCharactersPtr(cachedRegex->setToString))) : ((cachedRegex->buffer != NULL) && (cachedRegex->setToHash == cachedRegex->buffer->hash) && (cachedRegex->setToLength == cachedRegex->buffer->length) && (cachedRegex->setToUniChar == cachedRegex->buffer->uniChar)), &exception, exitNow);
  
  switch(maskedRegexOp) {
    case RKLRangeOp:
      if((RKL_EXPECTED(rkl_search(cachedRegex, matchRange, 0UL, &exception, &status) == NO, 0L)) || (RKL_EXPECTED(status > U_ZERO_ERROR, 0L))) { *(NSRange *)result = NSNotFoundRange; goto exitNow; }
      if(RKL_EXPECTED(capture == 0L, 1L)) { *(NSRange *)result = cachedRegex->lastMatchRange; } else { if(RKL_EXPECTED(rkl_getRangeForCapture(cachedRegex, &status, (int32_t)capture, (NSRange *)result) > U_ZERO_ERROR, 0L)) { goto exitNow; } }
      break;
      
    case RKLSplitOp:                         // Fall-thru...
    case RKLArrayOfStringsOp:                // Fall-thru...
    case RKLCapturesArrayOp:                 // Fall-thru...
    case RKLArrayOfCapturesOp:               // Fall-thru...
    case RKLDictionaryOfCapturesOp:          // Fall-thru...
    case RKLArrayOfDictionariesOfCapturesOp:
      findAll = rkl_makeFindAll(stackRanges, *matchRange, 2048L, (2048UL * sizeof(NSRange)), 0UL, &rkl_scratchBuffer[0], &rkl_scratchBuffer[1], &rkl_scratchBuffer[2], &rkl_scratchBuffer[3], &rkl_scratchBuffer[4], 0L, capture, (((maskedRegexOp == RKLCapturesArrayOp) || (maskedRegexOp == RKLDictionaryOfCapturesOp)) ? 1L : NSIntegerMax));
      
      if(RKL_EXPECTED(rkl_findRanges(cachedRegex, regexOp, &findAll, &exception, &status) == NO, 1L)) {
        if(RKL_EXPECTED(findAll.found == 0L, 0L)) { resultObject = (maskedRegexOp == RKLDictionaryOfCapturesOp) ? [NSDictionary dictionary] : [NSArray array]; }
        else {
          if(dictionaryOp == YES) { resultObject = rkl_makeDictionary (cachedRegex, regexOp, &findAll, captureKeysCount, captureKeys, captureKeyIndexes, &exception); }
          else                    { resultObject = rkl_makeArray      (cachedRegex, regexOp, &findAll, &exception); }
        }
      }
      
      for(tmpIdx = 0UL; tmpIdx < _RKL_SCRATCH_BUFFERS; tmpIdx++) { if(RKL_EXPECTED(rkl_scratchBuffer[tmpIdx] != NULL, 0L)) { rkl_scratchBuffer[tmpIdx] = rkl_free(&rkl_scratchBuffer[tmpIdx]); } }

      break;

    case RKLReplaceOp: resultObject = rkl_replaceString(cachedRegex, matchString, stringU16Length, replacementString, (NSUInteger)CFStringGetLength((CFStringRef)replacementString), (NSInteger *)result, (replaceMutable = (((regexOp & RKLReplaceMutable) != 0) ? 1UL : 0UL)), &exception, &status); break;

    default:           exception    = RKLCAssertDictionary(@"Unknown regexOp code."); break;
  }
  
exitNow:
  OSSpinLockUnlock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLUnlockedCacheSpinLock; // Warning about rkl_cacheSpinLockStatus never being read can be safely ignored.
  
  if(RKL_EXPECTED(status     > U_ZERO_ERROR, 0L) && RKL_EXPECTED(exception == NULL, 0L)) { exception = rkl_NSExceptionForRegex(regexString, options, NULL, status); } // If we had a problem, prepare an exception to be thrown.
  if(RKL_EXPECTED(exception != NULL,         0L))                                        { rkl_handleDelayedAssert(self, _cmd, exception);                          } // If there is an exception, throw it at this point.
  // If we're working on a mutable string and there were successful matches/replacements, then we still have work to do.
  // This is done outside the cache lock and with the objc replaceCharactersInRange:withString: method because Core Foundation
  // does not assert that the string we are attempting to update is actually a mutable string, whereas Foundation ensures
  // the object receiving the message is a mutable string and throws an exception if we're attempting to modify an immutable string.
  if(RKL_EXPECTED(replaceMutable == 1UL, 0L) && RKL_EXPECTED(*((NSInteger *)result) > 0L, 1L) && RKL_EXPECTED(status == U_ZERO_ERROR, 1L) && RKL_EXPECTED(resultObject != NULL, 1L)) { [matchString replaceCharactersInRange:*matchRange withString:resultObject]; }
  // If status < U_ZERO_ERROR, consider it an error, even though status < U_ZERO_ERROR is a 'warning' in ICU nomenclature.
  // status > U_ZERO_ERROR are an exception and handled above.
  // http://sourceforge.net/tracker/?func=detail&atid=990188&aid=2890810&group_id=204582
  if(RKL_EXPECTED(status  < U_ZERO_ERROR, 0L) && RKL_EXPECTED(resultObject == NULL, 0L) && (error != NULL)) {
    NSString *replacedString = NULL;
    NSInteger replacedCount = 0L;
    RKLUserInfoOptions userInfoOptions = RKLUserInfoNone;
    if((maskedRegexOp == RKLReplaceOp) && (result != NULL)) { userInfoOptions |= RKLUserInfoReplacedCount; replacedString = resultObject; replacedCount = *((NSInteger *)result); }
    if(matchRange != NULL) { userInfoOptions |= RKLUserInfoSubjectRange; }
    *error = rkl_makeNSError(userInfoOptions, regexString, options, NULL, status, matchString, (matchRange != NULL) ? *matchRange : NSNotFoundRange, replacementString, replacedString, replacedCount, (RKLRegexEnumerationOptions)RKLRegexEnumerationNoOptions, @"The ICU library returned an unexpected error.");
  }
  return(resultObject);
}

static void rkl_handleDelayedAssert(id self, SEL _cmd, id exception) {
  if(RKL_EXPECTED(exception != NULL, 1L)) {
    if([exception isKindOfClass:[NSException class]]) { [[NSException exceptionWithName:[exception name] reason:rkl_stringFromClassAndMethod(self, _cmd, [exception reason]) userInfo:[exception userInfo]] raise]; }
    else {
      id functionString = [exception objectForKey:@"function"], fileString = [exception objectForKey:@"file"], descriptionString = [exception objectForKey:@"description"], lineNumber = [exception objectForKey:@"line"];
      RKLCHardAbortAssert((functionString != NULL) && (fileString != NULL) && (descriptionString != NULL) && (lineNumber != NULL));
      [[NSAssertionHandler currentHandler] handleFailureInFunction:functionString file:fileString lineNumber:(NSInteger)[lineNumber longValue] description:@"%@", descriptionString];
    }
  }
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called from rkl_performRegexOp() or rkl_findRanges().
//  ----------

#pragma mark Primary means of performing a search with a regular expression

static NSUInteger rkl_search(RKLCachedRegex *cachedRegex, NSRange *searchRange, NSUInteger updateSearchRange, id *exception RKL_UNUSED_ASSERTION_ARG, int32_t *status) {
  NSUInteger foundMatch = 0UL;

  if((NSEqualRanges(*searchRange, cachedRegex->lastFindRange) == YES) && ((cachedRegex->lastMatchRange.length > 0UL) || (cachedRegex->lastMatchRange.location == (NSUInteger)NSNotFound))) { foundMatch = ((cachedRegex->lastMatchRange.location == (NSUInteger)NSNotFound) ? 0UL : 1UL);}
  else { // Only perform an expensive 'find' operation iff the current find range is different than the last find range.
    NSUInteger findLocation = (searchRange->location - cachedRegex->setToRange.location);
    RKLCDelayedAssert(((searchRange->location >= cachedRegex->setToRange.location)) && (NSRangeInsideRange(*searchRange, cachedRegex->setToRange) == YES) && (findLocation < INT_MAX) && (findLocation <= cachedRegex->setToRange.length), exception, exitNow);
    
    RKL_PREFETCH_UNICHAR(cachedRegex->setToUniChar, searchRange->location); // Spool up the CPU caches.
    
    // Using uregex_findNext can be a slight performance win.
    NSUInteger useFindNext = (RKL_EXPECTED(searchRange->location == (NSMaxRange(cachedRegex->lastMatchRange) + ((RKL_EXPECTED(cachedRegex->lastMatchRange.length == 0UL, 0L) && RKL_EXPECTED(cachedRegex->lastMatchRange.location < NSMaxRange(cachedRegex->setToRange), 0L)) ? 1UL : 0UL)), 1L) ? 1UL : 0UL);

    cachedRegex->lastFindRange = *searchRange;
    if(RKL_EXPECTED(useFindNext == 0UL, 0L)) { if(RKL_EXPECTED((RKL_ICU_FUNCTION_APPEND(uregex_find)    (cachedRegex->icu_regex, (int32_t)findLocation, status) == NO), 0L) || RKL_EXPECTED(*status > U_ZERO_ERROR, 0L)) { goto finishedFind; } }
    else {                                     if(RKL_EXPECTED((RKL_ICU_FUNCTION_APPEND(uregex_findNext)(cachedRegex->icu_regex,                        status) == NO), 0L) || RKL_EXPECTED(*status > U_ZERO_ERROR, 0L)) { goto finishedFind; } }
    foundMatch = 1UL; 
    
    if(RKL_EXPECTED(rkl_getRangeForCapture(cachedRegex, status, 0, &cachedRegex->lastMatchRange) > U_ZERO_ERROR, 0L)) { goto finishedFind; }
    RKLCDelayedAssert(NSRangeInsideRange(cachedRegex->lastMatchRange, *searchRange) == YES, exception, exitNow);
  }
  
finishedFind:
  if(RKL_EXPECTED(*status > U_ZERO_ERROR, 0L)) { foundMatch = 0UL; cachedRegex->lastFindRange = NSNotFoundRange; }
  
  if(RKL_EXPECTED(foundMatch == 0UL, 0L)) { cachedRegex->lastFindRange = NSNotFoundRange; cachedRegex->lastMatchRange = NSNotFoundRange; if(RKL_EXPECTED(updateSearchRange == 1UL, 1L)) { *searchRange = NSMakeRange(NSMaxRange(*searchRange), 0UL); } }
  else {
    RKLCDelayedAssert(NSRangeInsideRange(cachedRegex->lastMatchRange, *searchRange) == YES, exception, exitNow);
    if(RKL_EXPECTED(updateSearchRange == 1UL, 1L)) {
      NSUInteger nextLocation = (NSMaxRange(cachedRegex->lastMatchRange) + ((RKL_EXPECTED(cachedRegex->lastMatchRange.length == 0UL, 0L) && RKL_EXPECTED(cachedRegex->lastMatchRange.location < NSMaxRange(cachedRegex->setToRange), 1L)) ? 1UL : 0UL)), locationDiff = nextLocation - searchRange->location;
      RKLCDelayedAssert((((locationDiff > 0UL) || ((locationDiff == 0UL) && (cachedRegex->lastMatchRange.location == NSMaxRange(cachedRegex->setToRange)))) && (locationDiff <= searchRange->length)), exception, exitNow);
      searchRange->location  = nextLocation;
      searchRange->length   -= locationDiff;
    }
  }
  
#ifndef NS_BLOCK_ASSERTIONS
exitNow:
#endif
  return(foundMatch);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called from rkl_performRegexOp() or rkl_performEnumerationUsingBlock().
//  ----------

#pragma mark Used to perform multiple searches at once and return the NSRange results in bulk

static BOOL rkl_findRanges(RKLCachedRegex *cachedRegex, RKLRegexOp regexOp, RKLFindAll *findAll, id *exception, int32_t *status) {
  BOOL returnWithError = YES;
  RKLCDelayedAssert((((cachedRegex != NULL) && (cachedRegex->icu_regex != NULL) && (cachedRegex->setToUniChar != NULL) && (cachedRegex->captureCount >= 0L) && (cachedRegex->setToRange.location != (NSUInteger)NSNotFound)) && (status != NULL) && ((findAll != NULL) && (findAll->found == 0L) && (findAll->addedSplitRanges == 0L) && ((findAll->capacity >= 0L) && (((findAll->capacity > 0L) || (findAll->size > 0UL)) ? ((findAll->ranges != NULL) && (findAll->capacity > 0L) && (findAll->size > 0UL)) : 1)) && ((findAll->capture >= 0L) && (findAll->capture <= cachedRegex->captureCount)))), exception, exitNow);
  
  NSInteger  captureCount  = cachedRegex->captureCount, findAllRangeIndexOfLastNonZeroLength = 0L;
  NSUInteger lastLocation  = findAll->findInRange.location;
  RKLRegexOp maskedRegexOp = (regexOp & RKLMaskOp);
  NSRange    searchRange   = findAll->findInRange;

  for(findAll->found = 0L; (findAll->found < findAll->findUpTo) && ((findAll->found < findAll->capacity) || (findAll->found == 0L)); findAll->found++) {
    NSInteger loopCapture, shouldBreak = 0L;

    if(RKL_EXPECTED(findAll->found >= ((findAll->capacity - ((captureCount + 2L) * 4L)) - 4L), 0L)) { if(RKL_EXPECTED(rkl_growFindRanges(cachedRegex, lastLocation, findAll, exception) == 0UL, 0L)) { goto exitNow; } }
    
    RKLCDelayedAssert((searchRange.location != (NSUInteger)NSNotFound) && (NSRangeInsideRange(searchRange, cachedRegex->setToRange) == YES) && (NSRangeInsideRange(findAll->findInRange, cachedRegex->setToRange) == YES), exception, exitNow);
    
    // This fixes a 'bug' that is also present in ICU's uregex_split().  'Bug', in this case, means that the results of a split operation can differ from those that perl's split() creates for the same input.
    // "I|at|ice I eat rice" split using the regex "\b\s*" demonstrates the problem. ICU bug http://bugs.icu-project.org/trac/ticket/6826
    // ICU : "", "I", "|", "at", "|", "ice", "", "I", "", "eat", "", "rice" <- Results that RegexKitLite used to produce.
    // PERL:     "I", "|", "at", "|", "ice",     "I",     "eat",     "rice" <- Results that RegexKitLite now produces.
    do { if((rkl_search(cachedRegex, &searchRange, 1UL, exception, status) == NO) || (RKL_EXPECTED(*status > U_ZERO_ERROR, 0L))) { shouldBreak = 1L; } findAll->remainingRange = searchRange; }
    while(RKL_EXPECTED((cachedRegex->lastMatchRange.location - lastLocation) == 0UL, 0L) && RKL_EXPECTED(cachedRegex->lastMatchRange.length == 0UL, 0L) && (maskedRegexOp == RKLSplitOp) && RKL_EXPECTED(shouldBreak == 0L, 1L));
    if(RKL_EXPECTED(shouldBreak == 1L, 0L)) { break; }

    RKLCDelayedAssert((searchRange.location != (NSUInteger)NSNotFound) && (NSRangeInsideRange(searchRange, cachedRegex->setToRange) == YES) && (NSRangeInsideRange(findAll->findInRange, cachedRegex->setToRange) == YES) && (NSRangeInsideRange(searchRange, findAll->findInRange) == YES), exception, exitNow);
    RKLCDelayedAssert((NSRangeInsideRange(cachedRegex->lastFindRange, cachedRegex->setToRange) == YES) && (NSRangeInsideRange(cachedRegex->lastMatchRange, cachedRegex->setToRange) == YES) && (NSRangeInsideRange(cachedRegex->lastMatchRange, findAll->findInRange) == YES), exception, exitNow);
    RKLCDelayedAssert((findAll->ranges != NULL) && (findAll->found >= 0L) && (findAll->capacity >= 0L) && ((findAll->found + (captureCount + 3L) + 1L) < (findAll->capacity - 2L)), exception, exitNow);
    
    NSInteger findAllRangesIndexForCapture0 = findAll->found;
    switch(maskedRegexOp) {
      case RKLArrayOfStringsOp:
        if(findAll->capture == 0L) { findAll->ranges[findAll->found] = cachedRegex->lastMatchRange; } else { if(RKL_EXPECTED(rkl_getRangeForCapture(cachedRegex, status, (int32_t)findAll->capture, &findAll->ranges[findAll->found]) > U_ZERO_ERROR, 0L)) { goto exitNow; } }
        break;
        
      case RKLSplitOp:                         // Fall-thru...
      case RKLCapturesArrayOp:                 // Fall-thru...
      case RKLDictionaryOfCapturesOp:          // Fall-thru...
      case RKLArrayOfDictionariesOfCapturesOp: // Fall-thru...
      case RKLArrayOfCapturesOp:
        findAll->ranges[findAll->found] = ((maskedRegexOp == RKLSplitOp) ? NSMakeRange(lastLocation, cachedRegex->lastMatchRange.location - lastLocation) : cachedRegex->lastMatchRange);

        for(loopCapture = 1L; loopCapture <= captureCount; loopCapture++) {
          RKLCDelayedAssert((findAll->found >= 0L) && (findAll->found < (findAll->capacity - 2L)) && (loopCapture < INT_MAX), exception, exitNow);
          if(RKL_EXPECTED(rkl_getRangeForCapture(cachedRegex, status, (int32_t)loopCapture, &findAll->ranges[++findAll->found]) > U_ZERO_ERROR, 0L)) { goto exitNow; }
        }
        break;
        
      default: if(*exception == NULL) { *exception = RKLCAssertDictionary(@"Unknown regexOp."); } goto exitNow; break;
    }
    
    if(findAll->ranges[findAllRangesIndexForCapture0].length > 0UL) { findAllRangeIndexOfLastNonZeroLength = findAll->found + 1UL; }
    lastLocation = NSMaxRange(cachedRegex->lastMatchRange);
  }
  
  if(RKL_EXPECTED(*status > U_ZERO_ERROR, 0L)) { goto exitNow; }
  
  RKLCDelayedAssert((findAll->ranges != NULL) && (findAll->found >= 0L) && (findAll->found < (findAll->capacity - 2L)), exception, exitNow);
  if(maskedRegexOp == RKLSplitOp) {
    if(lastLocation != NSMaxRange(findAll->findInRange)) { findAll->addedSplitRanges++; findAll->ranges[findAll->found++] = NSMakeRange(lastLocation, NSMaxRange(findAll->findInRange) - lastLocation); findAllRangeIndexOfLastNonZeroLength = findAll->found; }
    findAll->found = findAllRangeIndexOfLastNonZeroLength;
  }
  
  RKLCDelayedAssert((findAll->ranges != NULL) && (findAll->found >= 0L) && (findAll->found < (findAll->capacity - 2L)), exception, exitNow);
  returnWithError = NO;
  
exitNow:
  return(returnWithError);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called from rkl_findRanges().
//  ----------

static NSUInteger rkl_growFindRanges(RKLCachedRegex *cachedRegex, NSUInteger lastLocation, RKLFindAll *findAll, id *exception RKL_UNUSED_ASSERTION_ARG) {
  NSUInteger didGrowRanges = 0UL;
  RKLCDelayedAssert((((cachedRegex != NULL) && (cachedRegex->captureCount >= 0L)) && ((findAll != NULL) && (findAll->capacity >= 0L) && (findAll->rangesScratchBuffer != NULL) && (findAll->found >= 0L) && (((findAll->capacity > 0L) || (findAll->size > 0UL) || (findAll->ranges != NULL)) ? ((findAll->capacity > 0L) && (findAll->size > 0UL) && (findAll->ranges != NULL) && (((size_t)findAll->capacity * sizeof(NSRange)) == findAll->size)) : 1))), exception, exitNow);
  
  // Attempt to guesstimate the required capacity based on: the total length needed to search / (length we've searched so far / ranges found so far).
  NSInteger newCapacity = (findAll->capacity + (findAll->capacity / 2L)), estimate = (NSInteger)((float)cachedRegex->setToLength / (((float)lastLocation + 1.0f) / ((float)findAll->found + 1.0f)));
  newCapacity = (((newCapacity + ((estimate > newCapacity) ? estimate : newCapacity)) / 2L) + ((cachedRegex->captureCount + 2L) * 4L) + 4L);
  
  NSUInteger                               needToCopy = ((*findAll->rangesScratchBuffer != findAll->ranges) && (findAll->ranges != NULL)) ? 1UL : 0UL; // If findAll->ranges is set to a stack allocation then we need to manually copy the data from the stack to the new heap allocation.
  size_t                                   newSize    = ((size_t)newCapacity * sizeof(NSRange));
  RKL_STRONG_REF NSRange * RKL_GC_VOLATILE newRanges  = NULL;
  
  if(RKL_EXPECTED((newRanges = (RKL_STRONG_REF NSRange * RKL_GC_VOLATILE)rkl_realloc((RKL_STRONG_REF void ** RKL_GC_VOLATILE)findAll->rangesScratchBuffer, newSize, 0UL)) == NULL, 0L)) { findAll->capacity = 0L; findAll->size = 0UL; findAll->ranges = NULL; *findAll->rangesScratchBuffer = rkl_free((RKL_STRONG_REF void ** RKL_GC_VOLATILE)findAll->rangesScratchBuffer); goto exitNow; } else { didGrowRanges = 1UL; }
  if(needToCopy == 1UL) { memcpy(newRanges, findAll->ranges, findAll->size); } // If necessary, copy the existing data to the new heap allocation.
  
  findAll->capacity = newCapacity;
  findAll->size     = newSize;
  findAll->ranges   = newRanges;
  
exitNow:
  return(didGrowRanges);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called from rkl_performRegexOp().
//  ----------

#pragma mark Convert bulk results from rkl_findRanges in to various NSArray types

static NSArray *rkl_makeArray(RKLCachedRegex *cachedRegex, RKLRegexOp regexOp, RKLFindAll *findAll, id *exception RKL_UNUSED_ASSERTION_ARG) {
  NSUInteger  createdStringsCount = 0UL,   createdArraysCount = 0UL,  transferredStringsCount = 0UL;
  id         * RKL_GC_VOLATILE matchedStrings = NULL, * RKL_GC_VOLATILE subcaptureArrays = NULL, emptyString = @"";
  NSArray    * RKL_GC_VOLATILE resultArray    = NULL;
  
  RKLCDelayedAssert((cachedRegex != NULL) && ((findAll != NULL) && (findAll->found >= 0L) && (findAll->stringsScratchBuffer != NULL) && (findAll->arraysScratchBuffer != NULL)), exception, exitNow);
  
  size_t      matchedStringsSize = ((size_t)findAll->found * sizeof(id));
  CFStringRef setToString        = cachedRegex->setToString;
  
  if((findAll->stackUsed + matchedStringsSize) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((matchedStrings = (id * RKL_GC_VOLATILE)alloca(matchedStringsSize))                                                                   == NULL, 0L)) { goto exitNow; } findAll->stackUsed += matchedStringsSize; }
  else {                                                                     if(RKL_EXPECTED((matchedStrings = (id * RKL_GC_VOLATILE)rkl_realloc(findAll->stringsScratchBuffer, matchedStringsSize, (NSUInteger)RKLScannedOption)) == NULL, 0L)) { goto exitNow; } }
  
  { // This sub-block (and its local variables) is here for the benefit of the optimizer.
    NSUInteger     found             = (NSUInteger)findAll->found;
    const NSRange *rangePtr          = findAll->ranges;
    id            *matchedStringsPtr = matchedStrings;
    
    for(createdStringsCount = 0UL; createdStringsCount < found; createdStringsCount++) {
      NSRange range = *rangePtr++;
      if(RKL_EXPECTED(((*matchedStringsPtr++ = RKL_EXPECTED(range.length == 0UL, 0L) ? emptyString : rkl_CreateStringWithSubstring((id)setToString, range)) == NULL), 0L)) { goto exitNow; }
    }
  }
  
  NSUInteger           arrayCount   = createdStringsCount;
  id * RKL_GC_VOLATILE arrayObjects = matchedStrings;
  
  if((regexOp & RKLSubcapturesArray) != 0UL) {
    RKLCDelayedAssert(((createdStringsCount % ((NSUInteger)cachedRegex->captureCount + 1UL)) == 0UL) && (createdArraysCount == 0UL), exception, exitNow);
    
    NSUInteger captureCount          = ((NSUInteger)cachedRegex->captureCount + 1UL);
    NSUInteger subcaptureArraysCount = (createdStringsCount / captureCount);
    size_t     subcaptureArraysSize  = ((size_t)subcaptureArraysCount * sizeof(id));
    
    if((findAll->stackUsed + subcaptureArraysSize) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((subcaptureArrays = (id * RKL_GC_VOLATILE)alloca(subcaptureArraysSize))                                                                  == NULL, 0L)) { goto exitNow; } findAll->stackUsed += subcaptureArraysSize; }
    else {                                                                       if(RKL_EXPECTED((subcaptureArrays = (id * RKL_GC_VOLATILE)rkl_realloc(findAll->arraysScratchBuffer, subcaptureArraysSize, (NSUInteger)RKLScannedOption)) == NULL, 0L)) { goto exitNow; } }
    
    { // This sub-block (and its local variables) is here for the benefit of the optimizer.
      id *subcaptureArraysPtr = subcaptureArrays;
      id *matchedStringsPtr   = matchedStrings;
      
      for(createdArraysCount = 0UL; createdArraysCount < subcaptureArraysCount; createdArraysCount++) {
        if(RKL_EXPECTED((*subcaptureArraysPtr++ = rkl_CreateArrayWithObjects((void **)matchedStringsPtr, captureCount)) == NULL, 0L)) { goto exitNow; }
        matchedStringsPtr       += captureCount;
        transferredStringsCount += captureCount;
      }
    }
    
    RKLCDelayedAssert((transferredStringsCount == createdStringsCount), exception, exitNow);
    arrayCount   = createdArraysCount;
    arrayObjects = subcaptureArrays;
  }
  
  RKLCDelayedAssert((arrayObjects != NULL), exception, exitNow);
  resultArray = rkl_CreateAutoreleasedArray((void **)arrayObjects, (NSUInteger)arrayCount);
  
exitNow:
  if(RKL_EXPECTED(resultArray == NULL, 0L) && (rkl_collectingEnabled() == NO)) { // If we did not create an array then we need to make sure that we release any objects we created.
    NSUInteger x;
    if(matchedStrings   != NULL) { for(x = transferredStringsCount; x < createdStringsCount; x++) { if((matchedStrings[x]  != NULL) && (matchedStrings[x] != emptyString)) { matchedStrings[x]   = rkl_ReleaseObject(matchedStrings[x]);   } } }
    if(subcaptureArrays != NULL) { for(x = 0UL;                     x < createdArraysCount;  x++) { if(subcaptureArrays[x] != NULL)                                        { subcaptureArrays[x] = rkl_ReleaseObject(subcaptureArrays[x]); } } }
  }
  
  return(resultArray);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called from rkl_performRegexOp().
//  ----------

#pragma mark Convert bulk results from rkl_findRanges in to various NSDictionary types

static id rkl_makeDictionary(RKLCachedRegex *cachedRegex, RKLRegexOp regexOp, RKLFindAll *findAll, NSUInteger captureKeysCount, id captureKeys[captureKeysCount], const int captureKeyIndexes[captureKeysCount], id *exception RKL_UNUSED_ASSERTION_ARG) {
  NSUInteger                      matchedStringIndex  = 0UL, createdStringsCount = 0UL, createdDictionariesCount = 0UL, matchedDictionariesCount = (findAll->found / (cachedRegex->captureCount + 1UL)), transferredDictionariesCount = 0UL;
  id           *  RKL_GC_VOLATILE matchedStrings      = NULL, * RKL_GC_VOLATILE matchedKeys = NULL, emptyString = @"";
  id              RKL_GC_VOLATILE returnObject        = NULL;
  NSDictionary ** RKL_GC_VOLATILE matchedDictionaries = NULL;
  
  RKLCDelayedAssert((cachedRegex != NULL) && ((findAll != NULL) && (findAll->found >= 0L) && (findAll->stringsScratchBuffer != NULL) && (findAll->dictionariesScratchBuffer != NULL) && (findAll->keysScratchBuffer != NULL) && (captureKeyIndexes != NULL)), exception, exitNow);
  
  CFStringRef setToString = cachedRegex->setToString;
  
  size_t      matchedStringsSize     = ((size_t)captureKeysCount * sizeof(void *));
  if((findAll->stackUsed + matchedStringsSize) < (size_t)_RKL_STACK_LIMIT) {      if(RKL_EXPECTED((matchedStrings      = (id           *  RKL_GC_VOLATILE)alloca(matchedStringsSize))                                                                             == NULL, 0L)) { goto exitNow; } findAll->stackUsed += matchedStringsSize; }
  else {                                                                          if(RKL_EXPECTED((matchedStrings      = (id           *  RKL_GC_VOLATILE)rkl_realloc(findAll->stringsScratchBuffer,      matchedStringsSize,      (NSUInteger)RKLScannedOption)) == NULL, 0L)) { goto exitNow; } }
  
  size_t      matchedKeysSize        = ((size_t)captureKeysCount * sizeof(void *));
  if((findAll->stackUsed + matchedKeysSize) < (size_t)_RKL_STACK_LIMIT) {         if(RKL_EXPECTED((matchedKeys         = (id           *  RKL_GC_VOLATILE)alloca(matchedKeysSize))                                                                                == NULL, 0L)) { goto exitNow; } findAll->stackUsed += matchedKeysSize; }
  else {                                                                          if(RKL_EXPECTED((matchedKeys         = (id           *  RKL_GC_VOLATILE)rkl_realloc(findAll->keysScratchBuffer,         matchedKeysSize,         (NSUInteger)RKLScannedOption)) == NULL, 0L)) { goto exitNow; } }
  
  size_t      matchedDictionariesSize = ((size_t)matchedDictionariesCount * sizeof(NSDictionary *));
  if((findAll->stackUsed + matchedDictionariesSize) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((matchedDictionaries = (NSDictionary ** RKL_GC_VOLATILE)alloca(matchedDictionariesSize))                                                                        == NULL, 0L)) { goto exitNow; } findAll->stackUsed += matchedDictionariesSize; }
  else {                                                                          if(RKL_EXPECTED((matchedDictionaries = (NSDictionary ** RKL_GC_VOLATILE)rkl_realloc(findAll->dictionariesScratchBuffer, matchedDictionariesSize, (NSUInteger)RKLScannedOption)) == NULL, 0L)) { goto exitNow; } }
  
  { // This sub-block (and its local variables) is here for the benefit of the optimizer.
    NSUInteger     captureCount           = cachedRegex->captureCount;
    NSDictionary **matchedDictionariesPtr = matchedDictionaries;
    
    for(createdDictionariesCount = 0UL; createdDictionariesCount < matchedDictionariesCount; createdDictionariesCount++) {
      RKLCDelayedAssert(((createdDictionariesCount * captureCount) < (NSUInteger)findAll->found), exception, exitNow);
      RKL_STRONG_REF const NSRange * RKL_GC_VOLATILE rangePtr = &findAll->ranges[(createdDictionariesCount * (captureCount + 1UL))];
      for(matchedStringIndex = 0UL; matchedStringIndex < captureKeysCount; matchedStringIndex++) {
        NSRange range = rangePtr[captureKeyIndexes[matchedStringIndex]];
        if(RKL_EXPECTED(range.location != NSNotFound, 0L)) {
          if(RKL_EXPECTED(((matchedStrings[createdStringsCount] = RKL_EXPECTED(range.length == 0UL, 0L) ? emptyString : rkl_CreateStringWithSubstring((id)setToString, range)) == NULL), 0L)) { goto exitNow; }
          matchedKeys[createdStringsCount] = captureKeys[createdStringsCount];
          createdStringsCount++;
        }
      }
      RKLCDelayedAssert((matchedStringIndex <= captureCount), exception, exitNow);
      if(RKL_EXPECTED(((*matchedDictionariesPtr++ = (NSDictionary * RKL_GC_VOLATILE)CFDictionaryCreate(NULL, (const void **)matchedKeys, (const void **)matchedStrings, (CFIndex)createdStringsCount, &rkl_transferOwnershipDictionaryKeyCallBacks, &rkl_transferOwnershipDictionaryValueCallBacks)) == NULL), 0L)) { goto exitNow; }
      createdStringsCount = 0UL;
    }
  }
  
  if(createdDictionariesCount > 0UL) {
    if((regexOp & RKLMaskOp) == RKLArrayOfDictionariesOfCapturesOp) {
      RKLCDelayedAssert((matchedDictionaries != NULL) && (createdDictionariesCount > 0UL), exception, exitNow);
      if((returnObject = rkl_CreateAutoreleasedArray((void **)matchedDictionaries, createdDictionariesCount)) == NULL) { goto exitNow; }
      transferredDictionariesCount = createdDictionariesCount;
    } else {
      RKLCDelayedAssert((matchedDictionaries != NULL) && (createdDictionariesCount == 1UL), exception, exitNow);
      if((returnObject = rkl_CFAutorelease(matchedDictionaries[0])) == NULL) { goto exitNow; }
      transferredDictionariesCount = 1UL;
    }
  }
  
exitNow:
  RKLCDelayedAssert((createdDictionariesCount <= transferredDictionariesCount) && ((transferredDictionariesCount > 0UL) ? (createdStringsCount == 0UL) : 1), exception, exitNow2);
#ifndef NS_BLOCK_ASSERTIONS
exitNow2:
#endif

  if(rkl_collectingEnabled() == NO) { // Release any objects, if necessary.
    NSUInteger x;
    if(matchedStrings      != NULL) { for(x = 0UL;                          x < createdStringsCount;      x++) { if((matchedStrings[x]      != NULL) && (matchedStrings[x] != emptyString)) { matchedStrings[x]      = rkl_ReleaseObject(matchedStrings[x]);      } } }
    if(matchedDictionaries != NULL) { for(x = transferredDictionariesCount; x < createdDictionariesCount; x++) { if((matchedDictionaries[x] != NULL))                                       { matchedDictionaries[x] = rkl_ReleaseObject(matchedDictionaries[x]); } } }
  }
  
  return(returnObject);
}

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  IMPORTANT!   Should only be called from rkl_performRegexOp().
//  ----------

#pragma mark Perform "search and replace" operations on strings using ICUs uregex_*replace* functions

static NSString *rkl_replaceString(RKLCachedRegex *cachedRegex, id searchString, NSUInteger searchU16Length, NSString *replacementString, NSUInteger replacementU16Length, NSInteger *replacedCountPtr, NSUInteger replaceMutable, id *exception, int32_t *status) {
  RKL_STRONG_REF UniChar       * RKL_GC_VOLATILE tempUniCharBuffer  = NULL;
  RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE replacementUniChar = NULL;
  uint64_t           searchU16Length64  = (uint64_t)searchU16Length, replacementU16Length64 = (uint64_t)replacementU16Length;
  int32_t            resultU16Length    = 0, tempUniCharBufferU16Capacity = 0, needU16Capacity = 0;
  id RKL_GC_VOLATILE resultObject       = NULL;
  NSInteger          replacedCount      = -1L;
  
  if((RKL_EXPECTED(replacementU16Length64 >= (uint64_t)INT_MAX, 0L) || RKL_EXPECTED(((searchU16Length64 / 2ULL) + (replacementU16Length64 * 2ULL)) >= (uint64_t)INT_MAX, 0L))) { *exception = [NSException exceptionWithName:NSRangeException reason:@"Replacement string length exceeds INT_MAX." userInfo:NULL]; goto exitNow; }

  RKLCDelayedAssert((searchU16Length64 < (uint64_t)INT_MAX) && (replacementU16Length64 < (uint64_t)INT_MAX) && (((searchU16Length64 / 2ULL) + (replacementU16Length64 * 2ULL)) < (uint64_t)INT_MAX), exception, exitNow);
  
  // Zero order approximation of the buffer sizes for holding the replaced string or split strings and split strings pointer offsets.  As UTF16 code units.
  tempUniCharBufferU16Capacity = (int32_t)(16UL + (searchU16Length + (searchU16Length / 2UL)) + (replacementU16Length * 2UL));
  RKLCDelayedAssert((tempUniCharBufferU16Capacity < INT_MAX) && (tempUniCharBufferU16Capacity > 0), exception, exitNow);  

  // Buffer sizes converted from native units to bytes.
  size_t stackSize = 0UL, replacementSize = ((size_t)replacementU16Length * sizeof(UniChar)), tempUniCharBufferSize = ((size_t)tempUniCharBufferU16Capacity * sizeof(UniChar));
  
  // For the various buffers we require, we first try to allocate from the stack if we're not over the RKL_STACK_LIMIT.  If we are, switch to using the heap for the buffer.
  if((stackSize + tempUniCharBufferSize) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((tempUniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)alloca(tempUniCharBufferSize))                                  == NULL, 0L)) { goto exitNow; } stackSize += tempUniCharBufferSize; }
  else                                                               { if(RKL_EXPECTED((tempUniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_realloc(&rkl_scratchBuffer[0], tempUniCharBufferSize, 0UL)) == NULL, 0L)) { goto exitNow; } }
  
  // Try to get the pointer to the replacement strings UTF16 data.  If we can't, allocate some buffer space, then covert to UTF16.
  if((replacementUniChar = CFStringGetCharactersPtr((CFStringRef)replacementString)) == NULL) {
    RKL_STRONG_REF UniChar * RKL_GC_VOLATILE uniCharBuffer = NULL;
    if((stackSize + replacementSize) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((uniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)alloca(replacementSize))                                  == NULL, 0L)) { goto exitNow; } stackSize += replacementSize; } 
    else                                                         { if(RKL_EXPECTED((uniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_realloc(&rkl_scratchBuffer[1], replacementSize, 0UL)) == NULL, 0L)) { goto exitNow; } }
    CFStringGetCharacters((CFStringRef)replacementString, CFMakeRange(0L, replacementU16Length), uniCharBuffer); // Convert to a UTF16 string.
    replacementUniChar = uniCharBuffer;
  }
  
  resultU16Length = rkl_replaceAll(cachedRegex, replacementUniChar, (int32_t)replacementU16Length, tempUniCharBuffer, tempUniCharBufferU16Capacity, &replacedCount, &needU16Capacity, exception, status);
  RKLCDelayedAssert((resultU16Length <= tempUniCharBufferU16Capacity) && (needU16Capacity >= resultU16Length) && (needU16Capacity >= 0), exception, exitNow);
  if(RKL_EXPECTED((needU16Capacity + 4) >= INT_MAX, 0L)) { *exception = [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Replaced string length exceeds INT_MAX." userInfo:NULL]; goto exitNow; }
  
  if(RKL_EXPECTED(*status == U_BUFFER_OVERFLOW_ERROR, 0L)) { // Our buffer guess(es) were too small.  Resize the buffers and try again.
    // rkl_replaceAll will turn a status of U_STRING_NOT_TERMINATED_WARNING in to a U_BUFFER_OVERFLOW_ERROR.
    // As an extra precaution, we pad out the amount needed by an extra four characters "just in case".
    // http://lists.apple.com/archives/Cocoa-dev/2010/Jan/msg01011.html
    needU16Capacity += 4;
    tempUniCharBufferSize = ((size_t)(tempUniCharBufferU16Capacity = needU16Capacity + 4) * sizeof(UniChar)); // Use needU16Capacity. Bug 2890810.
    if((stackSize + tempUniCharBufferSize) < (size_t)_RKL_STACK_LIMIT) { if(RKL_EXPECTED((tempUniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)alloca(tempUniCharBufferSize))                                  == NULL, 0L)) { goto exitNow; } stackSize += tempUniCharBufferSize; } // Warning about stackSize can be safely ignored.
    else                                                               { if(RKL_EXPECTED((tempUniCharBuffer = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_realloc(&rkl_scratchBuffer[0], tempUniCharBufferSize, 0UL)) == NULL, 0L)) { goto exitNow; } }
    
    *status         = U_ZERO_ERROR; // Make sure the status var is cleared and try again.
    resultU16Length = rkl_replaceAll(cachedRegex, replacementUniChar, (int32_t)replacementU16Length, tempUniCharBuffer, tempUniCharBufferU16Capacity, &replacedCount, &needU16Capacity, exception, status);
    RKLCDelayedAssert((resultU16Length <= tempUniCharBufferU16Capacity) && (needU16Capacity >= resultU16Length) && (needU16Capacity >= 0), exception, exitNow);
  }
  
  // If status != U_ZERO_ERROR, consider it an error, even though status < U_ZERO_ERROR is a 'warning' in ICU nomenclature.
  // http://sourceforge.net/tracker/?func=detail&atid=990188&aid=2890810&group_id=204582
  if(RKL_EXPECTED(*status != U_ZERO_ERROR, 0L)) { goto exitNow; } // Something went wrong.

  RKLCDelayedAssert((replacedCount >= 0L), exception, exitNow);  
  if(RKL_EXPECTED(resultU16Length == 0, 0L)) { resultObject = @""; } // Optimize the case where the replaced text length == 0 with a @"" string.
  else if(RKL_EXPECTED((NSUInteger)resultU16Length == searchU16Length, 0L) && RKL_EXPECTED(replacedCount == 0L, 1L)) { // Optimize the case where the replacement == original by creating a copy. Very fast if self is immutable.
    if(replaceMutable == 0UL) { resultObject = rkl_CFAutorelease(CFStringCreateCopy(NULL, (CFStringRef)searchString)); } // .. but only if this is not replacing a mutable self.  Warning about potential leak can be safely ignored.
  } else { resultObject = rkl_CFAutorelease(CFStringCreateWithCharacters(NULL, tempUniCharBuffer, (CFIndex)resultU16Length)); } // otherwise, create a new string.  Warning about potential leak can be safely ignored.
  
  // If replaceMutable == 1UL, we don't do the replacement here.  We wait until after we return and unlock the cache lock.
  // This is because we may be trying to mutate an immutable string object.
  if((replaceMutable == 1UL) && RKL_EXPECTED(replacedCount > 0L, 1L)) { // We're working on a mutable string and there were successful matches with replaced text, so there's work to do.
    if(cachedRegex->buffer != NULL) { rkl_clearBuffer(cachedRegex->buffer, 0UL); cachedRegex->buffer = NULL; }
    NSUInteger  idx = 0UL;
    for(idx = 0UL; idx < _RKL_LRU_CACHE_SET_WAYS; idx++) {
      RKLBuffer *buffer = ((NSUInteger)cachedRegex->setToLength < _RKL_FIXED_LENGTH) ? &rkl_lruFixedBuffer[idx] : &rkl_lruDynamicBuffer[idx];
      if(RKL_EXPECTED(cachedRegex->setToString == buffer->string, 0L) && (cachedRegex->setToLength == buffer->length) && (cachedRegex->setToHash == buffer->hash)) { rkl_clearBuffer(buffer, 0UL); }
    }
    rkl_clearCachedRegexSetTo(cachedRegex); // Flush any cached information about this string since it will mutate.
  }
  
exitNow:
  if(RKL_EXPECTED(status == NULL, 0L) || RKL_EXPECTED(*status != U_ZERO_ERROR, 0L) || RKL_EXPECTED(exception == NULL, 0L) || RKL_EXPECTED(*exception != NULL, 0L)) { replacedCount = -1L; }
  if(rkl_scratchBuffer[0] != NULL) { rkl_scratchBuffer[0] = rkl_free(&rkl_scratchBuffer[0]); }
  if(rkl_scratchBuffer[1] != NULL) { rkl_scratchBuffer[1] = rkl_free(&rkl_scratchBuffer[1]); }
  if(replacedCountPtr     != NULL) { *replacedCountPtr    = replacedCount;                   }
  return(resultObject);
} // The two warnings about potential leaks can be safely ignored.

//  IMPORTANT!   Should only be called from rkl_replaceString().
//  ----------
//  Modified version of the ICU libraries uregex_replaceAll() that keeps count of the number of replacements made.

static int32_t rkl_replaceAll(RKLCachedRegex *cachedRegex, RKL_STRONG_REF const UniChar * RKL_GC_VOLATILE replacementUniChar, int32_t replacementU16Length, UniChar *replacedUniChar, int32_t replacedU16Capacity, NSInteger *replacedCount, int32_t *needU16Capacity, id *exception RKL_UNUSED_ASSERTION_ARG, int32_t *status) {
  int32_t    u16Length        = 0,   initialReplacedU16Capacity = replacedU16Capacity;
  NSUInteger bufferOverflowed = 0UL;
  NSInteger  replaced         = -1L;
  RKLCDelayedAssert((cachedRegex != NULL) && (replacementUniChar != NULL) && (replacedUniChar != NULL) && (replacedCount != NULL) && (needU16Capacity != NULL) && (status != NULL) && (replacementU16Length >= 0) && (replacedU16Capacity >= 0), exception, exitNow);

  cachedRegex->lastFindRange = cachedRegex->lastMatchRange = NSNotFoundRange; // Clear the cached find information for this regex so a subsequent find works correctly.
  RKL_ICU_FUNCTION_APPEND(uregex_reset)(cachedRegex->icu_regex, 0, status);
  
  // Work around for ICU uregex_reset() bug, see http://bugs.icu-project.org/trac/ticket/6545
  // http://sourceforge.net/tracker/index.php?func=detail&aid=2105213&group_id=204582&atid=990188
  if(RKL_EXPECTED(cachedRegex->setToRange.length == 0UL, 0L) && (*status == U_INDEX_OUTOFBOUNDS_ERROR)) { *status = U_ZERO_ERROR; }
  replaced = 0L;
  // This loop originally came from ICU source/i18n/uregex.cpp, uregex_replaceAll.
  // There is a bug in that code which causes the size of the buffer required for the replaced text to not be calculated correctly.
  // This contains a work around using the variable bufferOverflowed.
  // ICU bug: http://bugs.icu-project.org/trac/ticket/6656
  // http://sourceforge.net/tracker/index.php?func=detail&aid=2408447&group_id=204582&atid=990188
  while(RKL_ICU_FUNCTION_APPEND(uregex_findNext)(cachedRegex->icu_regex, status)) {
    replaced++;
    u16Length += RKL_ICU_FUNCTION_APPEND(uregex_appendReplacement)(cachedRegex->icu_regex, replacementUniChar, replacementU16Length, &replacedUniChar, &replacedU16Capacity, status);
    if(RKL_EXPECTED(*status == U_BUFFER_OVERFLOW_ERROR, 0L)) { bufferOverflowed = 1UL; *status = U_ZERO_ERROR; }
  }
  if(RKL_EXPECTED(*status == U_BUFFER_OVERFLOW_ERROR, 0L)) { bufferOverflowed = 1UL; *status = U_ZERO_ERROR; }
  if(RKL_EXPECTED(*status <= U_ZERO_ERROR, 1L))            { u16Length += RKL_ICU_FUNCTION_APPEND(uregex_appendTail)(cachedRegex->icu_regex, &replacedUniChar, &replacedU16Capacity, status); }
  
  // Try to work around a status of U_STRING_NOT_TERMINATED_WARNING.  For now, we treat it as a "Buffer Overflow" error.
  // As an extra precaution, in rkl_replaceString, we pad out the amount needed by an extra four characters "just in case".
  // http://lists.apple.com/archives/Cocoa-dev/2010/Jan/msg01011.html
  if(RKL_EXPECTED(*status == U_STRING_NOT_TERMINATED_WARNING, 0L)) { *status = U_BUFFER_OVERFLOW_ERROR; }

  // Check for status <= U_ZERO_ERROR (a 'warning' in ICU nomenclature) rather than just status == U_ZERO_ERROR.
  // Under just the right circumstances, status might be equal to U_STRING_NOT_TERMINATED_WARNING.  When this occurred,
  // rkl_replaceString would never get the U_BUFFER_OVERFLOW_ERROR status, and thus never grow the buffer to the size needed.
  // http://sourceforge.net/tracker/?func=detail&atid=990188&aid=2890810&group_id=204582
  if(RKL_EXPECTED(bufferOverflowed == 1UL, 0L) && RKL_EXPECTED(*status <= U_ZERO_ERROR, 1L)) { *status = U_BUFFER_OVERFLOW_ERROR; }

#ifndef   NS_BLOCK_ASSERTIONS
exitNow:
#endif // NS_BLOCK_ASSERTIONS
  if(RKL_EXPECTED(replacedCount   != NULL, 1L)) { *replacedCount   = replaced;  }
  if(RKL_EXPECTED(needU16Capacity != NULL, 1L)) { *needU16Capacity = u16Length; } // Use needU16Capacity to return the number of characters that are needed for the completely replaced string. Bug 2890810.
  return(initialReplacedU16Capacity - replacedU16Capacity);                       // Return the number of characters of replacedUniChar that were used.
}

#pragma mark Internal function used to check if a regular expression is valid.

static NSUInteger rkl_isRegexValid(id self, SEL _cmd, NSString *regex, RKLRegexOptions options, NSInteger *captureCountPtr, NSError **error) {
  volatile NSUInteger RKL_CLEANUP(rkl_cleanup_cacheSpinLockStatus) rkl_cacheSpinLockStatus = 0UL;
  
  RKLCachedRegex *cachedRegex    = NULL;
  NSUInteger      gotCachedRegex = 0UL;
  NSInteger       captureCount   = -1L;
  id              exception      = NULL;
  
  if((error != NULL) && (*error != NULL)) { *error = NULL; }
  if(RKL_EXPECTED(regex == NULL, 0L)) { RKL_RAISE_EXCEPTION(NSInvalidArgumentException, @"The regular expression argument is NULL."); }
  
  OSSpinLockLock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLLockedCacheSpinLock;
  rkl_dtrace_incrementEventID();
  if(RKL_EXPECTED((cachedRegex = rkl_getCachedRegex(regex, options, error, &exception)) != NULL, 1L)) { gotCachedRegex = 1UL; captureCount = cachedRegex->captureCount; }
  cachedRegex = NULL;
  OSSpinLockUnlock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLUnlockedCacheSpinLock; // Warning about rkl_cacheSpinLockStatus never being read can be safely ignored.
  
  if(captureCountPtr != NULL) { *captureCountPtr = captureCount; }
  if(RKL_EXPECTED(exception != NULL, 0L)) { rkl_handleDelayedAssert(self, _cmd, exception); }
  return(gotCachedRegex);
}

#pragma mark Functions used for clearing and releasing resources for various internal data structures

static void rkl_clearStringCache(void) {
  RKLCAbortAssert(rkl_cacheSpinLock != (OSSpinLock)0);
  rkl_lastCachedRegex = NULL;
  NSUInteger x = 0UL;
  for(x = 0UL; x < _RKL_SCRATCH_BUFFERS;    x++) { if(rkl_scratchBuffer[x] != NULL) { rkl_scratchBuffer[x] = rkl_free(&rkl_scratchBuffer[x]); }  }
  for(x = 0UL; x < _RKL_REGEX_CACHE_LINES;  x++) { rkl_clearCachedRegex(&rkl_cachedRegexes[x]);                                                  }
  for(x = 0UL; x < _RKL_LRU_CACHE_SET_WAYS; x++) { rkl_clearBuffer(&rkl_lruFixedBuffer[x], 0UL); rkl_clearBuffer(&rkl_lruDynamicBuffer[x], 1UL); }
}

static void rkl_clearBuffer(RKLBuffer *buffer, NSUInteger freeDynamicBuffer) {
  RKLCAbortAssert(buffer != NULL);
  if(RKL_EXPECTED(buffer == NULL, 0L)) { return; }
  if(RKL_EXPECTED(freeDynamicBuffer == 1UL,  0L) && RKL_EXPECTED(buffer->uniChar != NULL, 1L)) { RKL_STRONG_REF void * RKL_GC_VOLATILE p = (RKL_STRONG_REF void * RKL_GC_VOLATILE)buffer->uniChar; buffer->uniChar = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_free(&p); }
  if(RKL_EXPECTED(buffer->string    != NULL, 1L))                                              { CFRelease((CFTypeRef)buffer->string); buffer->string = NULL; }
  buffer->length = 0L;
  buffer->hash   = 0UL;
}

static void rkl_clearCachedRegex(RKLCachedRegex *cachedRegex) {
  RKLCAbortAssert(cachedRegex != NULL);
  if(RKL_EXPECTED(cachedRegex == NULL, 0L)) { return; }
  rkl_clearCachedRegexSetTo(cachedRegex);
  if(rkl_lastCachedRegex      == cachedRegex) { rkl_lastCachedRegex = NULL; }
  if(cachedRegex->icu_regex   != NULL)        { RKL_ICU_FUNCTION_APPEND(uregex_close)(cachedRegex->icu_regex); cachedRegex->icu_regex   = NULL; cachedRegex->captureCount = -1L;                               }
  if(cachedRegex->regexString != NULL)        { CFRelease((CFTypeRef)cachedRegex->regexString);                cachedRegex->regexString = NULL; cachedRegex->options      =  0U; cachedRegex->regexHash = 0UL; }
}

static void rkl_clearCachedRegexSetTo(RKLCachedRegex *cachedRegex) {
  RKLCAbortAssert(cachedRegex != NULL);
  if(RKL_EXPECTED(cachedRegex              == NULL, 0L)) { return; }
  if(RKL_EXPECTED(cachedRegex->icu_regex   != NULL, 1L)) { int32_t status = 0; RKL_ICU_FUNCTION_APPEND(uregex_setText)(cachedRegex->icu_regex, &rkl_emptyUniCharString[0], 0, &status); }
  if(RKL_EXPECTED(cachedRegex->setToString != NULL, 1L)) { CFRelease((CFTypeRef)cachedRegex->setToString); cachedRegex->setToString = NULL; }
  cachedRegex->lastFindRange    = cachedRegex->lastMatchRange       = cachedRegex->setToRange = NSNotFoundRange;
  cachedRegex->setToIsImmutable = cachedRegex->setToNeedsConversion = 0U;
  cachedRegex->setToUniChar     = NULL;
  cachedRegex->setToHash        = 0UL;
  cachedRegex->setToLength      = 0L;
  cachedRegex->buffer           = NULL;
}

#pragma mark Internal functions used to implement NSException and NSError functionality and userInfo NSDictionaries

// Helps to keep things tidy.
#define addKeyAndObject(objs, keys, i, k, o) ({id _o=(o), _k=(k); if((_o != NULL) && (_k != NULL)) { objs[i] = _o; keys[i] = _k; i++; } })

static NSDictionary *rkl_userInfoDictionary(RKLUserInfoOptions userInfoOptions, NSString *regexString, RKLRegexOptions options, const UParseError *parseError, int32_t status, NSString *matchString, NSRange matchRange, NSString *replacementString, NSString *replacedString, NSInteger replacedCount, RKLRegexEnumerationOptions enumerationOptions, ...) {
  va_list varArgsList;
  va_start(varArgsList, enumerationOptions);
  if(regexString == NULL) { regexString = @"<NULL regex>"; }

  id objects[64], keys[64];
  NSUInteger count = 0UL;
  
  NSString * RKL_GC_VOLATILE errorNameString = [NSString stringWithUTF8String:RKL_ICU_FUNCTION_APPEND(u_errorName)(status)];
  
  addKeyAndObject(objects, keys, count, RKLICURegexRegexErrorKey,        regexString);
  addKeyAndObject(objects, keys, count, RKLICURegexRegexOptionsErrorKey, [NSNumber numberWithUnsignedInt:options]);
  addKeyAndObject(objects, keys, count, RKLICURegexErrorCodeErrorKey,    [NSNumber numberWithInt:status]);
  addKeyAndObject(objects, keys, count, RKLICURegexErrorNameErrorKey,    errorNameString);

  if(matchString                                            != NULL) { addKeyAndObject(objects, keys, count, RKLICURegexSubjectStringErrorKey,      matchString);                                             }  
  if((userInfoOptions & RKLUserInfoSubjectRange)            != 0UL)  { addKeyAndObject(objects, keys, count, RKLICURegexSubjectRangeErrorKey,       [NSValue valueWithRange:matchRange]);                     }
  if(replacementString                                      != NULL) { addKeyAndObject(objects, keys, count, RKLICURegexReplacementStringErrorKey,  replacementString);                                       }
  if(replacedString                                         != NULL) { addKeyAndObject(objects, keys, count, RKLICURegexReplacedStringErrorKey,     replacedString);                                          }
  if((userInfoOptions & RKLUserInfoReplacedCount)           != 0UL)  { addKeyAndObject(objects, keys, count, RKLICURegexReplacedCountErrorKey,      [NSNumber numberWithInteger:replacedCount]);              }
  if((userInfoOptions & RKLUserInfoRegexEnumerationOptions) != 0UL)  { addKeyAndObject(objects, keys, count, RKLICURegexEnumerationOptionsErrorKey, [NSNumber numberWithUnsignedInteger:enumerationOptions]); }
  
  if((parseError != NULL) && (parseError->line != -1)) {
    NSString *preContextString  = [NSString stringWithCharacters:&parseError->preContext[0]  length:(NSUInteger)RKL_ICU_FUNCTION_APPEND(u_strlen)(&parseError->preContext[0])];
    NSString *postContextString = [NSString stringWithCharacters:&parseError->postContext[0] length:(NSUInteger)RKL_ICU_FUNCTION_APPEND(u_strlen)(&parseError->postContext[0])];
    
    addKeyAndObject(objects, keys, count, RKLICURegexLineErrorKey,        [NSNumber numberWithInt:parseError->line]);
    addKeyAndObject(objects, keys, count, RKLICURegexOffsetErrorKey,      [NSNumber numberWithInt:parseError->offset]);
    addKeyAndObject(objects, keys, count, RKLICURegexPreContextErrorKey,  preContextString);
    addKeyAndObject(objects, keys, count, RKLICURegexPostContextErrorKey, postContextString);
    addKeyAndObject(objects, keys, count, @"NSLocalizedFailureReason",    ([NSString stringWithFormat:@"The error %@ occurred at line %d, column %d: %@<<HERE>>%@", errorNameString, parseError->line, parseError->offset, preContextString, postContextString]));
  } else {
    addKeyAndObject(objects, keys, count, @"NSLocalizedFailureReason",    ([NSString stringWithFormat:@"The error %@ occurred.", errorNameString]));
  }
  
  while(count < 62UL) { id obj = va_arg(varArgsList, id), key = va_arg(varArgsList, id); if((obj != NULL) && (key != NULL)) { addKeyAndObject(objects, keys, count, key, obj); } else { break; } }
  va_end(varArgsList);
  
  return([NSDictionary dictionaryWithObjects:&objects[0] forKeys:&keys[0] count:count]);
}

static NSError *rkl_makeNSError(RKLUserInfoOptions userInfoOptions, NSString *regexString, RKLRegexOptions options, const UParseError *parseError, int32_t status, NSString *matchString, NSRange matchRange, NSString *replacementString, NSString *replacedString, NSInteger replacedCount, RKLRegexEnumerationOptions enumerationOptions, NSString *errorDescription) {
  if(errorDescription == NULL) { errorDescription = (status == U_ZERO_ERROR) ? @"No description of this error is available." : [NSString stringWithFormat:@"ICU regular expression error #%d, %s.", status, RKL_ICU_FUNCTION_APPEND(u_errorName)(status)]; }
  return([NSError errorWithDomain:RKLICURegexErrorDomain code:(NSInteger)status userInfo:rkl_userInfoDictionary(userInfoOptions, regexString, options, parseError, status, matchString, matchRange, replacementString, replacedString, replacedCount, enumerationOptions, errorDescription, @"NSLocalizedDescription", NULL)]);
}

static NSException *rkl_NSExceptionForRegex(NSString *regexString, RKLRegexOptions options, const UParseError *parseError, int32_t status) {
  return([NSException exceptionWithName:RKLICURegexException reason:[NSString stringWithFormat:@"ICU regular expression error #%d, %s.", status, RKL_ICU_FUNCTION_APPEND(u_errorName)(status)] userInfo:rkl_userInfoDictionary((RKLUserInfoOptions)RKLUserInfoNone, regexString, options, parseError, status, NULL, NSNotFoundRange, NULL, NULL, 0L, (RKLRegexEnumerationOptions)RKLRegexEnumerationNoOptions, NULL)]);
}

static NSDictionary *rkl_makeAssertDictionary(const char *function, const char *file, int line, NSString *format, ...) {
  va_list varArgsList;
  va_start(varArgsList, format);
  NSString * RKL_GC_VOLATILE formatString   = [[[NSString alloc] initWithFormat:format arguments:varArgsList] autorelease];
  va_end(varArgsList);
  NSString * RKL_GC_VOLATILE functionString = [NSString stringWithUTF8String:function], *fileString = [NSString stringWithUTF8String:file];
  return([NSDictionary dictionaryWithObjectsAndKeys:formatString, @"description", functionString, @"function", fileString, @"file", [NSNumber numberWithInt:line], @"line", NSInternalInconsistencyException, @"exceptionName", NULL]);
}

static NSString *rkl_stringFromClassAndMethod(id object, SEL selector, NSString *format, ...) {
  va_list varArgsList;
  va_start(varArgsList, format);
  NSString * RKL_GC_VOLATILE formatString = [[[NSString alloc] initWithFormat:format arguments:varArgsList] autorelease];
  va_end(varArgsList);
  Class objectsClass = (object == NULL) ? NULL : [object class];
  return([NSString stringWithFormat:@"*** %c[%@ %@]: %@", (object == objectsClass) ? '+' : '-', (objectsClass == NULL) ? @"<NULL>" : NSStringFromClass(objectsClass), (selector == NULL) ? @":NULL:" : NSStringFromSelector(selector), formatString]);
}

#ifdef    _RKL_BLOCKS_ENABLED

////////////
#pragma mark -
#pragma mark Objective-C ^Blocks Support
#pragma mark -
////////////

// Prototypes

static id rkl_performEnumerationUsingBlock(id self, SEL _cmd,
                                           RKLRegexOp regexOp, NSString *regexString, RKLRegexOptions options,
                                           id matchString, NSRange matchRange,
                                           RKLBlockEnumerationOp blockEnumerationOp, RKLRegexEnumerationOptions enumerationOptions,
                                           NSInteger *replacedCountPtr, NSUInteger *errorFreePtr,
                                           NSError **error,
                                           void (^stringsAndRangesBlock)(NSInteger capturedCount, NSString * const capturedStrings[capturedCount], const NSRange capturedStringRanges[capturedCount], volatile BOOL * const stop),
                                           NSString *(^replaceStringsAndRangesBlock)(NSInteger capturedCount, NSString * const capturedStrings[capturedCount], const NSRange capturedStringRanges[capturedCount], volatile BOOL * const stop)
                                           ) RKL_NONNULL_ARGS(1,2,4,6);

// This is an object meant for internal use only.  It wraps and abstracts various functionality to simplify ^Blocks support.

@interface RKLBlockEnumerationHelper : NSObject {
  @public
  RKLCachedRegex cachedRegex;
  RKLBuffer      buffer;
  RKL_STRONG_REF void * RKL_GC_VOLATILE scratchBuffer[_RKL_SCRATCH_BUFFERS];
  NSUInteger     needToFreeBufferUniChar:1;
}
- (id)initWithRegex:(NSString *)initRegexString options:(RKLRegexOptions)initOptions string:(NSString *)initString range:(NSRange)initRange error:(NSError **)initError;
@end

@implementation RKLBlockEnumerationHelper

- (id)initWithRegex:(NSString *)initRegexString options:(RKLRegexOptions)initOptions string:(NSString *)initString range:(NSRange)initRange error:(NSError **)initError
{
  volatile NSUInteger RKL_CLEANUP(rkl_cleanup_cacheSpinLockStatus) rkl_cacheSpinLockStatus = 0UL;

  int32_t         status               = U_ZERO_ERROR;
  id              exception            = NULL;
  RKLCachedRegex *retrievedCachedRegex = NULL;

#ifdef _RKL_DTRACE_ENABLED
  NSUInteger      thisDTraceEventID    = 0UL;
  unsigned int    lookupResultFlags    = 0U;
#endif
  
  if(RKL_EXPECTED((self = [super init]) == NULL, 0L)) { goto errorExit; }

  RKLCDelayedAssert((initRegexString != NULL) && (initString != NULL), &exception, errorExit);

  // IMPORTANT!   Once we have obtained the lock, code MUST exit via 'goto exitNow;' to unlock the lock!  NO EXCEPTIONS!
  // ----------
  OSSpinLockLock(&rkl_cacheSpinLock); // Grab the lock and get cache entry.
  rkl_cacheSpinLockStatus |= RKLLockedCacheSpinLock;
  rkl_dtrace_incrementAndGetEventID(thisDTraceEventID);
  
  if(RKL_EXPECTED((retrievedCachedRegex = rkl_getCachedRegex(initRegexString, initOptions, initError, &exception)) == NULL, 0L)) { goto exitNow; }
  RKLCDelayedAssert(((retrievedCachedRegex >= rkl_cachedRegexes) && ((retrievedCachedRegex - &rkl_cachedRegexes[0]) < (ssize_t)_RKL_REGEX_CACHE_LINES)) && (retrievedCachedRegex != NULL) && (retrievedCachedRegex->icu_regex != NULL) && (retrievedCachedRegex->regexString != NULL) && (retrievedCachedRegex->captureCount >= 0L) && (retrievedCachedRegex == rkl_lastCachedRegex), &exception, exitNow);
  
  if(RKL_EXPECTED(retrievedCachedRegex == NULL, 0L) || RKL_EXPECTED(status > U_ZERO_ERROR, 0L) || RKL_EXPECTED(exception != NULL, 0L)) { goto exitNow; }

  if(RKL_EXPECTED((cachedRegex.icu_regex   = RKL_ICU_FUNCTION_APPEND(uregex_clone)(retrievedCachedRegex->icu_regex, &status)) == NULL, 0L) || RKL_EXPECTED(status != U_ZERO_ERROR, 0L)) { goto exitNow; }
  if(RKL_EXPECTED((cachedRegex.regexString = (CFStringRef)CFRetain((CFTypeRef)retrievedCachedRegex->regexString))             == NULL, 0L))                                             { goto exitNow; }
  cachedRegex.options      = initOptions;
  cachedRegex.captureCount = retrievedCachedRegex->captureCount;
  cachedRegex.regexHash    = retrievedCachedRegex->regexHash;

  RKLCDelayedAssert((cachedRegex.icu_regex != NULL) && (cachedRegex.regexString != NULL) && (cachedRegex.captureCount >= 0L), &exception, exitNow);

exitNow:
  if((rkl_cacheSpinLockStatus & RKLLockedCacheSpinLock) != 0UL) { // In case we arrive at exitNow: without obtaining the rkl_cacheSpinLock.
    OSSpinLockUnlock(&rkl_cacheSpinLock);
    rkl_cacheSpinLockStatus |= RKLUnlockedCacheSpinLock; // Warning about rkl_cacheSpinLockStatus never being read can be safely ignored.
  }

  if(RKL_EXPECTED(self == NULL, 0L) || RKL_EXPECTED(retrievedCachedRegex == NULL, 0L) || RKL_EXPECTED(cachedRegex.icu_regex == NULL, 0L) || RKL_EXPECTED(status != U_ZERO_ERROR, 0L) || RKL_EXPECTED(exception != NULL, 0L)) { goto errorExit; }
  retrievedCachedRegex = NULL; // Since we no longer hold the lock, ensure that nothing accesses the retrieved cache regex after this point.

  rkl_dtrace_addLookupFlag(lookupResultFlags, RKLEnumerationBufferLookupFlag);

  if(RKL_EXPECTED((buffer.string = CFStringCreateCopy(NULL, (CFStringRef)initString)) == NULL, 0L)) { goto errorExit; }
  buffer.hash   = CFHash((CFTypeRef)buffer.string);
  buffer.length = CFStringGetLength(buffer.string);

  if((buffer.uniChar = (UniChar *)CFStringGetCharactersPtr(buffer.string)) == NULL) {
    rkl_dtrace_addLookupFlag(lookupResultFlags, RKLConversionRequiredLookupFlag);
    if(RKL_EXPECTED((buffer.uniChar = (RKL_STRONG_REF UniChar * RKL_GC_VOLATILE)rkl_realloc((RKL_STRONG_REF void ** RKL_GC_VOLATILE)&buffer.uniChar, ((size_t)buffer.length * sizeof(UniChar)), 0UL)) == NULL, 0L)) { goto errorExit; } // Resize the buffer.
    needToFreeBufferUniChar = rkl_collectingEnabled() ? 0U : 1U;
    CFStringGetCharacters(buffer.string, CFMakeRange(0L, buffer.length), (UniChar *)buffer.uniChar); // Convert to a UTF16 string.
  }

  if(RKL_EXPECTED((cachedRegex.setToString = (CFStringRef)CFRetain((CFTypeRef)buffer.string)) == NULL, 0L)) { goto errorExit; }
  cachedRegex.setToHash    = buffer.hash;
  cachedRegex.setToLength  = buffer.length;
  cachedRegex.setToUniChar = buffer.uniChar;
  cachedRegex.buffer       = &buffer;
  
  RKLCDelayedAssert((cachedRegex.icu_regex != NULL) && (cachedRegex.setToUniChar != NULL) && (cachedRegex.setToLength < INT_MAX) && (NSMaxRange(initRange) <= (NSUInteger)cachedRegex.setToLength) && (NSMaxRange(initRange) < INT_MAX), &exception, errorExit);
  cachedRegex.lastFindRange = cachedRegex.lastMatchRange = NSNotFoundRange;
  cachedRegex.setToRange    = initRange;
  RKL_ICU_FUNCTION_APPEND(uregex_setText)(cachedRegex.icu_regex, cachedRegex.setToUniChar + cachedRegex.setToRange.location, (int32_t)cachedRegex.setToRange.length, &status);
  if(RKL_EXPECTED(status > U_ZERO_ERROR, 0L)) { goto errorExit; }

  rkl_dtrace_addLookupFlag(lookupResultFlags, RKLSetTextLookupFlag);
  rkl_dtrace_utf16ConversionCacheWithEventID(thisDTraceEventID, lookupResultFlags, initString, cachedRegex.setToRange.location, cachedRegex.setToRange.length, cachedRegex.setToLength);

  return(self);

errorExit:
  if(RKL_EXPECTED(self      != NULL,         1L))                                        {  [self autorelease]; }
  if(RKL_EXPECTED(status     > U_ZERO_ERROR, 0L) && RKL_EXPECTED(exception == NULL, 0L)) {  exception = rkl_NSExceptionForRegex(initRegexString, initOptions, NULL, status); } // If we had a problem, prepare an exception to be thrown.
  if(RKL_EXPECTED(status     < U_ZERO_ERROR, 0L) && (initError != NULL))                 { *initError = rkl_makeNSError((RKLUserInfoOptions)RKLUserInfoNone, initRegexString, initOptions, NULL, status, initString, initRange, NULL, NULL, 0L, (RKLRegexEnumerationOptions)RKLRegexEnumerationNoOptions, @"The ICU library returned an unexpected error."); }
  if(RKL_EXPECTED(exception != NULL,         0L))                                        {  rkl_handleDelayedAssert(self, _cmd, exception); }

  return(NULL);
}

#ifdef    __OBJC_GC__
- (void)finalize
{
  rkl_clearCachedRegex(&cachedRegex);
  rkl_clearBuffer(&buffer, (needToFreeBufferUniChar != 0U) ? 1LU : 0LU);
  NSUInteger tmpIdx = 0UL; // The rkl_free() below is "probably" a no-op when GC is on, but better to be safe than sorry...
  for(tmpIdx = 0UL; tmpIdx < _RKL_SCRATCH_BUFFERS; tmpIdx++) { if(RKL_EXPECTED(scratchBuffer[tmpIdx] != NULL, 0L)) { scratchBuffer[tmpIdx] = rkl_free(&scratchBuffer[tmpIdx]); } }
  [super finalize];
}
#endif // __OBJC_GC__
  
- (void)dealloc
{
  rkl_clearCachedRegex(&cachedRegex);
  rkl_clearBuffer(&buffer, (needToFreeBufferUniChar != 0U) ? 1LU : 0LU);
  NSUInteger tmpIdx = 0UL;
  for(tmpIdx = 0UL; tmpIdx < _RKL_SCRATCH_BUFFERS; tmpIdx++) { if(RKL_EXPECTED(scratchBuffer[tmpIdx] != NULL, 0L)) { scratchBuffer[tmpIdx] = rkl_free(&scratchBuffer[tmpIdx]); } }
  [super dealloc];
}

@end

//  IMPORTANT!   This code is critical path code.  Because of this, it has been written for speed, not clarity.
//  ----------
//
//  Return value: BOOL. Per "Error Handling Programming Guide" wrt/ NSError, return NO on error / failure, and set *error to an NSError object.
//  
//  rkl_performEnumerationUsingBlock reference counted / manual memory management notes:
//
//  When running using reference counting, rkl_performEnumerationUsingBlock() creates a CFMutableArray called autoreleaseArray, which is -autoreleased.
//  autoreleaseArray uses the rkl_transferOwnershipArrayCallBacks CFArray callbacks which do not perform a -retain/CFRetain() when objects are added, but do perform a -release/CFRelease() when an object is removed.
//
//  A special class, RKLBlockEnumerationHelper, is used to manage the details of creating a private instantiation of the ICU regex (via uregex_clone()) and setting up the details of the UTF-16 buffer required by the ICU regex engine.
//  The instantiated RKLBlockEnumerationHelper is not autoreleased, but added to autoreleaseArray.  When rkl_performEnumerationUsingBlock() exits, it calls CFArrayRemoveAllValues(autoreleaseArray), which empties the array.
//  This has the effect of immediately -releasing the instantiated RKLBlockEnumerationHelper object, and all the memory used to hold the ICU regex and UTF-16 conversion buffer.
//  This means the memory is reclaimed immediately and we do not have to wait until the autorelease pool pops.
//
//  If we are performing a "string replacement" operation, we create a temporary NSMutableString named mutableReplacementString to hold the replaced strings results.  mutableReplacementString is also added to autoreleaseArray so that it
//  can be properly released on an error.
//
//  Temporary strings that are created during the enumeration of matches are added to autoreleaseArray.
//  The strings are added by doing a CFArrayReplaceValues(), which simultaneously releases the previous iterations temporary strings while adding the current iterations temporary strings to the array.
//
//  autoreleaseArray always has a reference to any "live" and in use objects. If anything "Goes Wrong", at any point, for any reason (ie, exception is thrown), autoreleaseArray is in the current NSAutoreleasePool
//  and will automatically be released when that pool pops.  This ensures that we don't leak anything even when things go seriously sideways.  This also allows us to keep the total amount of memory in use
//  down to a minimum, which can be substantial if the user is enumerating a large string, for example a regex of '\w+' on a 500K+ text file.
//
//  The only 'caveat' is that the user needs to -retain any strings that they want to use past the point at which their ^block returns.  Logically, it is as if the following takes place:
//  
//  for(eachMatchOfRegexInStringToSearch) {
//    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//    callUsersBlock(capturedCount, capturedStrings, capturedStringRanges, stop);
//    [pool release];
//  }
//
//  But in reality, no NSAutoreleasePool is created, it's all slight of hand done via the CFMutableArray autoreleaseArray.
//
//  rkl_performEnumerationUsingBlock garbage collected / automatic memory management notes:
//
//  When RegexKitLite is built with -fobjc-gc or -fobjc-gc-only, and (in the case of -fobjc-gc) RegexKitLite determines that GC is active at execution time, then rkl_performEnumerationUsingBlock essentially
//  skips all of the above reference counted autoreleaseArray stuff. 
//
//  rkl_performEnumerationUsingBlock and RKLRegexEnumerationReleaseStringReturnedByReplacementBlock notes
//
//  Under reference counting, this enumeration option allows the user to return a non-autoreleased string, and then have RegexKitLite send the object a -release message once it's done with it.
//  The primary reason to do this is to immediately reclaim the memory used by the string holding the replacement text.
//  Just in case the user returns one of the strings we passed via capturedStrings[], we check to see if the string return by the block is any of the strings we created and passed via capturedStrings[].
//  If it is one of our strings, we do not send the string a -release since that would over release it.  It is assumed that the user will /NOT/ add a -retain to our strings in this case.
//  Under GC, RKLRegexEnumerationReleaseStringReturnedByReplacementBlock is ignored and no -release messages are sent.
//  

#pragma mark Primary internal function that Objective-C ^Blocks related methods call to perform regular expression operations

static id rkl_performEnumerationUsingBlock(id self, SEL _cmd,
                                           RKLRegexOp regexOp, NSString *regexString, RKLRegexOptions options,
                                           id matchString, NSRange matchRange,
                                           RKLBlockEnumerationOp blockEnumerationOp, RKLRegexEnumerationOptions enumerationOptions,
                                           NSInteger *replacedCountPtr, NSUInteger *errorFreePtr,
                                           NSError **error,
                                           void (^stringsAndRangesBlock)(NSInteger capturedCount, NSString * const capturedStrings[capturedCount], const NSRange capturedStringRanges[capturedCount], volatile BOOL * const stop),
                                           NSString *(^replaceStringsAndRangesBlock)(NSInteger capturedCount, NSString * const capturedStrings[capturedCount], const NSRange capturedStringRanges[capturedCount], volatile BOOL * const stop)) {
  NSMutableArray            * RKL_GC_VOLATILE autoreleaseArray              = NULL;
  RKLBlockEnumerationHelper * RKL_GC_VOLATILE blockEnumerationHelper        = NULL;
  NSMutableString           * RKL_GC_VOLATILE mutableReplacementString      = NULL;
  RKL_STRONG_REF UniChar    * RKL_GC_VOLATILE blockEnumerationHelperUniChar = NULL;
  NSUInteger    errorFree                = NO;
  id            exception                = NULL, returnObject  = NULL;
  CFRange       autoreleaseReplaceRange  = CFMakeRange(0L, 0L);
  int32_t       status                   = U_ZERO_ERROR;
  RKLRegexOp    maskedRegexOp            = (regexOp & RKLMaskOp);
  volatile BOOL shouldStop               = NO;
  NSInteger     replacedCount            = -1L;
  NSRange       lastMatchedRange         = NSNotFoundRange;
  NSUInteger    stringU16Length          = 0UL;
  
  BOOL performStringReplacement = (blockEnumerationOp == RKLBlockEnumerationReplaceOp) ? YES : NO;
  
  if((error != NULL) && (*error != NULL)) { *error = NULL; }
  
  if(RKL_EXPECTED(regexString == NULL, 0L)) { exception = (id)RKL_EXCEPTION(NSInvalidArgumentException,       @"The regular expression argument is NULL."); goto exitNow; }
  if(RKL_EXPECTED(matchString == NULL, 0L)) { exception = (id)RKL_EXCEPTION(NSInternalInconsistencyException, @"The match string argument is NULL.");       goto exitNow; }

  if((((enumerationOptions & RKLRegexEnumerationCapturedStringsNotRequired)              != 0UL) && ((enumerationOptions & RKLRegexEnumerationFastCapturedStringsXXX) != 0UL)) ||
     (((enumerationOptions & RKLRegexEnumerationReleaseStringReturnedByReplacementBlock) != 0UL) && (blockEnumerationOp != RKLBlockEnumerationReplaceOp)) ||
     ((enumerationOptions & (~((RKLRegexEnumerationOptions)(RKLRegexEnumerationCapturedStringsNotRequired | RKLRegexEnumerationReleaseStringReturnedByReplacementBlock | RKLRegexEnumerationFastCapturedStringsXXX)))) != 0UL)) {
    exception = (id)RKL_EXCEPTION(NSInvalidArgumentException, @"The RKLRegexEnumerationOptions argument is not valid.");
    goto exitNow;
  }
  
  stringU16Length = (NSUInteger)CFStringGetLength((CFStringRef)matchString);
  
  if(RKL_EXPECTED(matchRange.length == NSUIntegerMax,          1L)) { matchRange.length = stringU16Length; } // For convenience.
  if(RKL_EXPECTED(stringU16Length    < NSMaxRange(matchRange), 0L)) { exception = (id)RKL_EXCEPTION(NSRangeException, @"Range or index out of bounds.");  goto exitNow; }
  if(RKL_EXPECTED(stringU16Length   >= (NSUInteger)INT_MAX,    0L)) { exception = (id)RKL_EXCEPTION(NSRangeException, @"String length exceeds INT_MAX."); goto exitNow; }
  
  RKLCDelayedAssert((self != NULL) && (_cmd != NULL) && ((blockEnumerationOp == RKLBlockEnumerationMatchOp) ? (((regexOp == RKLCapturesArrayOp) || (regexOp == RKLSplitOp)) && (stringsAndRangesBlock != NULL) && (replaceStringsAndRangesBlock == NULL)) : 1) && ((blockEnumerationOp == RKLBlockEnumerationReplaceOp) ? ((regexOp == RKLCapturesArrayOp) && (stringsAndRangesBlock == NULL) && (replaceStringsAndRangesBlock != NULL)) : 1) , &exception, exitNow);

  if((rkl_collectingEnabled() == NO) && RKL_EXPECTED((autoreleaseArray = rkl_CFAutorelease(CFArrayCreateMutable(NULL, 0L, &rkl_transferOwnershipArrayCallBacks))) == NULL, 0L))          { goto exitNow; } // Warning about potential leak of Core Foundation object can be safely ignored.
  if(RKL_EXPECTED((blockEnumerationHelper = [[RKLBlockEnumerationHelper alloc] initWithRegex:regexString options:options string:matchString range:matchRange error:error]) == NULL, 0L)) { goto exitNow; } // Warning about potential leak of blockEnumerationHelper can be safely ignored.
  if(autoreleaseArray != NULL) { CFArrayAppendValue((CFMutableArrayRef)autoreleaseArray, blockEnumerationHelper); autoreleaseReplaceRange.location++; } // We do not autorelease blockEnumerationHelper, but instead add it to autoreleaseArray.
  
  if(performStringReplacement == YES) {
    if(RKL_EXPECTED((mutableReplacementString = [[NSMutableString alloc] init]) == NULL, 0L)) { goto exitNow; } // Warning about potential leak of mutableReplacementString can be safely ignored.
    if(autoreleaseArray != NULL) { CFArrayAppendValue((CFMutableArrayRef)autoreleaseArray, mutableReplacementString); autoreleaseReplaceRange.location++; } // We do not autorelease mutableReplacementString, but instead add it to autoreleaseArray.
  }

  // RKLBlockEnumerationHelper creates an immutable copy of the string to match (matchString) which we reference via blockEnumerationHelperString.  We use blockEnumerationHelperString when creating the captured strings from a match.
  // This protects us against the user mutating matchString while we are in the middle of enumerating matches.
  NSString           * RKL_GC_VOLATILE blockEnumerationHelperString = (NSString *)blockEnumerationHelper->buffer.string, ** RKL_GC_VOLATILE capturedStrings = NULL, *emptyString = @"";
  CFMutableStringRef * RKL_GC_VOLATILE fastCapturedStrings          = NULL;
  NSInteger  captureCountBlockArgument = (blockEnumerationHelper->cachedRegex.captureCount + 1L);
  size_t     capturedStringsCapacity   = ((size_t)captureCountBlockArgument + 4UL);
  size_t     capturedRangesCapacity    = (((size_t)captureCountBlockArgument + 4UL) * 5UL);
  NSRange   *capturedRanges            = NULL;

  lastMatchedRange              = NSMakeRange(matchRange.location, 0UL);
  blockEnumerationHelperUniChar = blockEnumerationHelper->buffer.uniChar;
  
  RKLCDelayedAssert((blockEnumerationHelperString != NULL) && (blockEnumerationHelperUniChar != NULL) && (captureCountBlockArgument > 0L) && (capturedStringsCapacity > 0UL) && (capturedRangesCapacity > 0UL), &exception, exitNow);
  
  if((capturedStrings = (NSString ** RKL_GC_VOLATILE)alloca(sizeof(NSString *) * capturedStringsCapacity)) == NULL) { goto exitNow; } // Space to hold the captured strings from a match.
  if((capturedRanges  = (NSRange *)                  alloca(sizeof(NSRange)    * capturedRangesCapacity))  == NULL) { goto exitNow; } // Space to hold the NSRanges of the captured strings from a match.
  
#ifdef NS_BLOCK_ASSERTIONS
  { // Initialize the padded capturedStrings and capturedRanges to values that should tickle a fault if they are ever used.
    size_t idx = 0UL;
    for(idx = captureCountBlockArgument; idx < capturedStringsCapacity; idx++) { capturedStrings[idx] = (NSString *)RKLIllegalPointer; }
    for(idx = captureCountBlockArgument; idx < capturedRangesCapacity;  idx++) { capturedRanges[idx]  =             RKLIllegalRange;   }
  }
#else
  { // Initialize all of the capturedStrings and capturedRanges to values that should tickle a fault if they are ever used.
    size_t idx = 0UL;
    for(idx = 0UL; idx < capturedStringsCapacity; idx++) { capturedStrings[idx] = (NSString *)RKLIllegalPointer; }
    for(idx = 0UL; idx < capturedRangesCapacity;  idx++) { capturedRanges[idx]  =             RKLIllegalRange;   }
  }
#endif
  
  if((enumerationOptions & RKLRegexEnumerationFastCapturedStringsXXX) != 0UL) {
    RKLCDelayedAssert(((enumerationOptions & RKLRegexEnumerationCapturedStringsNotRequired) == 0UL), &exception, exitNow);
    size_t idx = 0UL;
    if((fastCapturedStrings = (CFMutableStringRef * RKL_GC_VOLATILE)alloca(sizeof(NSString *) * capturedStringsCapacity)) == NULL) { goto exitNow; } // Space to hold the "fast" captured strings from a match.

    for(idx = 0UL; idx < (size_t)captureCountBlockArgument; idx++) {
      if((fastCapturedStrings[idx] = CFStringCreateMutableWithExternalCharactersNoCopy(NULL, NULL, 0L, 0L, kCFAllocatorNull)) == NULL) { goto exitNow; }
      if(autoreleaseArray != NULL) { CFArrayAppendValue((CFMutableArrayRef)autoreleaseArray, fastCapturedStrings[idx]); autoreleaseReplaceRange.location++; } // We do not autorelease mutableReplacementString, but instead add it to autoreleaseArray.
      capturedStrings[idx] = (NSString *)fastCapturedStrings[idx];
    }
  }

  RKLFindAll findAll = rkl_makeFindAll(capturedRanges, matchRange, (NSInteger)capturedRangesCapacity, (capturedRangesCapacity * sizeof(NSRange)), 0UL, &blockEnumerationHelper->scratchBuffer[0], &blockEnumerationHelper->scratchBuffer[1], &blockEnumerationHelper->scratchBuffer[2], &blockEnumerationHelper->scratchBuffer[3], &blockEnumerationHelper->scratchBuffer[4], 0L, 0L, 1L);
  
  NSString ** RKL_GC_VOLATILE capturedStringsBlockArgument = NULL; // capturedStringsBlockArgument is what we pass to the 'capturedStrings[]' argument of the users ^block.  Will pass NULL if the user doesn't want the captured strings created automatically.
  if((enumerationOptions & RKLRegexEnumerationCapturedStringsNotRequired) == 0UL) { capturedStringsBlockArgument = capturedStrings; } // If the user wants the captured strings automatically created, set to capturedStrings.
  
  replacedCount = 0L;
  while(RKL_EXPECTED(rkl_findRanges(&blockEnumerationHelper->cachedRegex, regexOp, &findAll, &exception, &status) == NO, 1L) && RKL_EXPECTED(findAll.found > 0L, 1L) && RKL_EXPECTED(exception == NULL, 1L) && RKL_EXPECTED(status == U_ZERO_ERROR, 1L)) {
    if(performStringReplacement == YES) {
      NSUInteger lastMatchedMaxLocation = (lastMatchedRange.location + lastMatchedRange.length);
      NSRange    previousUnmatchedRange = NSMakeRange(lastMatchedMaxLocation, findAll.ranges[0].location - lastMatchedMaxLocation);
      RKLCDelayedAssert((NSMaxRange(previousUnmatchedRange) <= stringU16Length) && (NSRangeInsideRange(previousUnmatchedRange, matchRange) == YES), &exception, exitNow);
      if(RKL_EXPECTED(previousUnmatchedRange.length > 0UL, 1L)) { CFStringAppendCharacters((CFMutableStringRef)mutableReplacementString, blockEnumerationHelperUniChar + previousUnmatchedRange.location, (CFIndex)previousUnmatchedRange.length); }
    }

    findAll.found -= findAll.addedSplitRanges;

    NSInteger passCaptureCountBlockArgument = ((findAll.found == 0L) && (findAll.addedSplitRanges == 1L) && (maskedRegexOp == RKLSplitOp)) ? 1L : findAll.found, capturedStringsIdx = passCaptureCountBlockArgument;
    RKLCDelayedHardAssert(passCaptureCountBlockArgument <= captureCountBlockArgument, &exception, exitNow);
    if(capturedStringsBlockArgument != NULL) { // Only create the captured strings if the user has requested them.
      BOOL hadError = NO;                      // Loop over all the strings rkl_findRanges found.  If rkl_CreateStringWithSubstring() returns NULL due to an error, set returnBool to NO, and break out of the for() loop.

      for(capturedStringsIdx = 0L; capturedStringsIdx < passCaptureCountBlockArgument; capturedStringsIdx++) {
        RKLCDelayedHardAssert(capturedStringsIdx < captureCountBlockArgument, &exception, exitNow);
        if((enumerationOptions & RKLRegexEnumerationFastCapturedStringsXXX) != 0UL) {
          // Analyzer report of "Dereference of null pointer" can be safely ignored for the next line.  Bug filed: http://llvm.org/bugs/show_bug.cgi?id=6150
          CFStringSetExternalCharactersNoCopy(fastCapturedStrings[capturedStringsIdx], &blockEnumerationHelperUniChar[findAll.ranges[capturedStringsIdx].location], (CFIndex)findAll.ranges[capturedStringsIdx].length, (CFIndex)findAll.ranges[capturedStringsIdx].length);
        } else {
          if((capturedStrings[capturedStringsIdx] = (findAll.ranges[capturedStringsIdx].length == 0UL) ? emptyString : rkl_CreateStringWithSubstring(blockEnumerationHelperString, findAll.ranges[capturedStringsIdx])) == NULL) { hadError = YES; break; }
        }
      }
      if(((enumerationOptions & RKLRegexEnumerationFastCapturedStringsXXX) == 0UL) && RKL_EXPECTED(autoreleaseArray != NULL, 1L)) { CFArrayReplaceValues((CFMutableArrayRef)autoreleaseArray, autoreleaseReplaceRange, (const void **)capturedStrings, capturedStringsIdx); autoreleaseReplaceRange.length = capturedStringsIdx; } // Add to autoreleaseArray all the strings the for() loop created.
      if(RKL_EXPECTED(hadError == YES,  0L)) { goto exitNow; }           // hadError == YES will be set if rkl_CreateStringWithSubstring() returned NULL.
    }
    // For safety, set any capturedRanges and capturedStrings up to captureCountBlockArgument + 1 to values that indicate that they are not valid.
    // These values are chosen such that they should tickle any misuse by users.
    // capturedStringsIdx is initialized to passCaptureCountBlockArgument, but if capturedStringsBlockArgument != NULL, it is reset to 0 by the loop that creates strings.
    // If the loop that creates strings has an error, execution should transfer to exitNow and this will never get run.
    // Again, this is for safety for users that do not check the passed block argument 'captureCount' and instead depend on something like [regex captureCount].
    for(; capturedStringsIdx < captureCountBlockArgument + 1L; capturedStringsIdx++) { RKLCDelayedAssert((capturedStringsIdx < (NSInteger)capturedStringsCapacity) && (capturedStringsIdx < (NSInteger)capturedRangesCapacity), &exception, exitNow); capturedRanges[capturedStringsIdx] = RKLIllegalRange; capturedStrings[capturedStringsIdx] = (NSString *)RKLIllegalPointer; }

    RKLCDelayedAssert((passCaptureCountBlockArgument > 0L) && (NSMaxRange(capturedRanges[0]) <= stringU16Length) && (capturedRanges[0].location < NSIntegerMax) && (capturedRanges[0].length < NSIntegerMax), &exception, exitNow);

    switch(blockEnumerationOp) {
      case RKLBlockEnumerationMatchOp: stringsAndRangesBlock(passCaptureCountBlockArgument, capturedStringsBlockArgument, capturedRanges, &shouldStop); break;

      case RKLBlockEnumerationReplaceOp: {
          NSString *blockReturnedReplacementString = replaceStringsAndRangesBlock(passCaptureCountBlockArgument, capturedStringsBlockArgument, capturedRanges, &shouldStop);
    
          if(RKL_EXPECTED(blockReturnedReplacementString != NULL, 1L)) {
            CFStringAppend((CFMutableStringRef)mutableReplacementString, (CFStringRef)blockReturnedReplacementString);
            BOOL shouldRelease = (((enumerationOptions & RKLRegexEnumerationReleaseStringReturnedByReplacementBlock) != 0UL) && (capturedStringsBlockArgument != NULL) && (rkl_collectingEnabled() == NO)) ? YES : NO;
            if(shouldRelease == YES) { NSInteger idx = 0L; for(idx = 0L; idx < passCaptureCountBlockArgument; idx++) { if(capturedStrings[idx] == blockReturnedReplacementString) { shouldRelease = NO; break; } } }
            if(shouldRelease == YES) { [blockReturnedReplacementString release]; }
          }
      }
      break;

      default: exception = RKLCAssertDictionary(@"Unknown blockEnumerationOp code."); goto exitNow; break;
    }
    
    replacedCount++;    
    findAll.addedSplitRanges = 0L;                     // rkl_findRanges() expects findAll.addedSplitRanges to be 0 on entry.
    findAll.found            = 0L;                     // rkl_findRanges() expects findAll.found to be 0 on entry.
    findAll.findInRange      = findAll.remainingRange; // Ask rkl_findRanges() to search the part of the string after the current match.
    lastMatchedRange         = findAll.ranges[0];

    if(RKL_EXPECTED(shouldStop != NO, 0L)) { break; }
  }
  errorFree = YES;
  
exitNow:
  if(RKL_EXPECTED(errorFree == NO, 0L)) { replacedCount = -1L; }
  if((blockEnumerationOp == RKLBlockEnumerationReplaceOp) && RKL_EXPECTED(errorFree == YES, 1L)) {
    RKLCDelayedAssert(replacedCount >= 0L, &exception, exitNow2);
    if(RKL_EXPECTED(replacedCount == 0UL, 0L)) {
      RKLCDelayedAssert((blockEnumerationHelper != NULL) && (blockEnumerationHelper->buffer.string != NULL), &exception, exitNow2);
      returnObject = rkl_CreateStringWithSubstring((id)blockEnumerationHelper->buffer.string, matchRange);
      if(rkl_collectingEnabled() == NO) { returnObject = rkl_CFAutorelease(returnObject); }
    }
    else {
      NSUInteger lastMatchedMaxLocation = (lastMatchedRange.location + lastMatchedRange.length);
      NSRange    previousUnmatchedRange = NSMakeRange(lastMatchedMaxLocation, NSMaxRange(matchRange) - lastMatchedMaxLocation);
      RKLCDelayedAssert((NSMaxRange(previousUnmatchedRange) <= stringU16Length) && (NSRangeInsideRange(previousUnmatchedRange, matchRange) == YES), &exception, exitNow2);
      
      if(RKL_EXPECTED(previousUnmatchedRange.length > 0UL, 1L)) { CFStringAppendCharacters((CFMutableStringRef)mutableReplacementString, blockEnumerationHelperUniChar + previousUnmatchedRange.location, (CFIndex)previousUnmatchedRange.length); }
      returnObject = rkl_CFAutorelease(CFStringCreateCopy(NULL, (CFStringRef)mutableReplacementString)); // Warning about potential leak of Core Foundation object can be safely ignored.
    }
  }
  
#ifndef   NS_BLOCK_ASSERTIONS
exitNow2:
#endif // NS_BLOCK_ASSERTIONS
  if(RKL_EXPECTED(autoreleaseArray != NULL, 1L)) { CFArrayRemoveAllValues((CFMutableArrayRef)autoreleaseArray); } // Causes blockEnumerationHelper to be released immediately, freeing all of its resources (such as a large UTF-16 conversion buffer).
  if(RKL_EXPECTED(exception        != NULL, 0L)) { rkl_handleDelayedAssert(self, _cmd, exception);              } // If there is an exception, throw it at this point.
  if(((errorFree == NO) || ((errorFree == YES) && (returnObject == NULL))) && (error != NULL) && (*error == NULL)) {
    RKLUserInfoOptions  userInfoOptions = (RKLUserInfoSubjectRange | RKLUserInfoRegexEnumerationOptions);
    NSString           *replacedString  = NULL;
    if(blockEnumerationOp == RKLBlockEnumerationReplaceOp) { userInfoOptions |= RKLUserInfoReplacedCount; if(RKL_EXPECTED(errorFree == YES, 1L)) { replacedString = returnObject; } }
    *error = rkl_makeNSError(userInfoOptions, regexString, options, NULL, status, (blockEnumerationHelper != NULL) ? (blockEnumerationHelper->buffer.string != NULL) ? (NSString *)blockEnumerationHelper->buffer.string : matchString : matchString, matchRange, NULL, replacedString, replacedCount, enumerationOptions, @"An unexpected error occurred.");
  }
  if(replacedCountPtr != NULL) { *replacedCountPtr = replacedCount; }
  if(errorFreePtr     != NULL) { *errorFreePtr     = errorFree;     }
  return(returnObject);
} // The two warnings about potential leaks can be safely ignored.

#endif // _RKL_BLOCKS_ENABLED

////////////
#pragma mark -
#pragma mark Objective-C Public Interface
#pragma mark -
////////////

@implementation NSString (RegexKitLiteAdditions)

#pragma mark +clearStringCache

+ (void)RKL_METHOD_PREPEND(clearStringCache)
{
  volatile NSUInteger RKL_CLEANUP(rkl_cleanup_cacheSpinLockStatus) rkl_cacheSpinLockStatus = 0UL;
  OSSpinLockLock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLLockedCacheSpinLock;
  rkl_clearStringCache();
  OSSpinLockUnlock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLUnlockedCacheSpinLock; // Warning about rkl_cacheSpinLockStatus never being read can be safely ignored.
}

#pragma mark +captureCountForRegex:

+ (NSInteger)RKL_METHOD_PREPEND(captureCountForRegex):(NSString *)regex
{
  NSInteger captureCount = -1L;
  rkl_isRegexValid(self, _cmd, regex, RKLNoOptions, &captureCount, NULL);
  return(captureCount);
}

+ (NSInteger)RKL_METHOD_PREPEND(captureCountForRegex):(NSString *)regex options:(RKLRegexOptions)options error:(NSError **)error
{
  NSInteger captureCount = -1L;
  rkl_isRegexValid(self, _cmd, regex, options,      &captureCount, error);
  return(captureCount);
}

#pragma mark -captureCount:

- (NSInteger)RKL_METHOD_PREPEND(captureCount)
{
  NSInteger captureCount = -1L;
  rkl_isRegexValid(self, _cmd, self, RKLNoOptions,  &captureCount, NULL);
  return(captureCount);
}

- (NSInteger)RKL_METHOD_PREPEND(captureCountWithOptions):(RKLRegexOptions)options error:(NSError **)error
{
  NSInteger captureCount = -1L;
  rkl_isRegexValid(self, _cmd, self, options,       &captureCount, error);
  return(captureCount);
}

#pragma mark -componentsSeparatedByRegex:

- (NSArray *)RKL_METHOD_PREPEND(componentsSeparatedByRegex):(NSString *)regex
{
  NSRange range = NSMaxiumRange;
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLSplitOp, regex, RKLNoOptions, 0L, self, &range, NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(componentsSeparatedByRegex):(NSString *)regex range:(NSRange)range
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLSplitOp, regex, RKLNoOptions, 0L, self, &range, NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(componentsSeparatedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLSplitOp, regex, options,      0L, self, &range, NULL, error, NULL, 0UL, NULL, NULL));
}

#pragma mark -isMatchedByRegex:

- (BOOL)RKL_METHOD_PREPEND(isMatchedByRegex):(NSString *)regex
{
  NSRange result = NSNotFoundRange, range = NSMaxiumRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions, 0L, self, &range, NULL, NULL,  &result, 0UL, NULL, NULL);
  return((result.location == (NSUInteger)NSNotFound) ? NO : YES);
}

- (BOOL)RKL_METHOD_PREPEND(isMatchedByRegex):(NSString *)regex inRange:(NSRange)range
{
  NSRange result = NSNotFoundRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions, 0L, self, &range, NULL, NULL,  &result, 0UL, NULL, NULL);
  return((result.location == (NSUInteger)NSNotFound) ? NO : YES);
}

- (BOOL)RKL_METHOD_PREPEND(isMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error
{
  NSRange result = NSNotFoundRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, options,      0L, self, &range, NULL, error, &result, 0UL, NULL, NULL);
  return((result.location == (NSUInteger)NSNotFound) ? NO : YES);
}

#pragma mark -isRegexValid

- (BOOL)RKL_METHOD_PREPEND(isRegexValid)
{
  return(rkl_isRegexValid(self, _cmd, self, RKLNoOptions, NULL, NULL)  == 1UL ? YES : NO);
}

- (BOOL)RKL_METHOD_PREPEND(isRegexValidWithOptions):(RKLRegexOptions)options error:(NSError **)error
{
  return(rkl_isRegexValid(self, _cmd, self, options,      NULL, error) == 1UL ? YES : NO);
}

#pragma mark -flushCachedRegexData

- (void)RKL_METHOD_PREPEND(flushCachedRegexData)
{
  volatile NSUInteger RKL_CLEANUP(rkl_cleanup_cacheSpinLockStatus) rkl_cacheSpinLockStatus = 0UL;

  CFIndex    selfLength = CFStringGetLength((CFStringRef)self);
  CFHashCode selfHash   = CFHash((CFTypeRef)self);
  
  OSSpinLockLock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLLockedCacheSpinLock;
  rkl_dtrace_incrementEventID();

  NSUInteger idx;
  for(idx = 0UL; idx < _RKL_REGEX_CACHE_LINES; idx++) {
    RKLCachedRegex *cachedRegex = &rkl_cachedRegexes[idx];
    if((cachedRegex->setToString != NULL) && ( (cachedRegex->setToString == (CFStringRef)self) || ((cachedRegex->setToLength == selfLength) && (cachedRegex->setToHash == selfHash)) ) ) { rkl_clearCachedRegexSetTo(cachedRegex); }
  }
  for(idx = 0UL; idx < _RKL_LRU_CACHE_SET_WAYS; idx++) { RKLBuffer *buffer = &rkl_lruFixedBuffer[idx];   if((buffer->string != NULL) && ((buffer->string == (CFStringRef)self) || ((buffer->length == selfLength) && (buffer->hash == selfHash)))) { rkl_clearBuffer(buffer, 0UL); } }
  for(idx = 0UL; idx < _RKL_LRU_CACHE_SET_WAYS; idx++) { RKLBuffer *buffer = &rkl_lruDynamicBuffer[idx]; if((buffer->string != NULL) && ((buffer->string == (CFStringRef)self) || ((buffer->length == selfLength) && (buffer->hash == selfHash)))) { rkl_clearBuffer(buffer, 0UL); } }

  OSSpinLockUnlock(&rkl_cacheSpinLock);
  rkl_cacheSpinLockStatus |= RKLUnlockedCacheSpinLock; // Warning about rkl_cacheSpinLockStatus never being read can be safely ignored.
}

#pragma mark -rangeOfRegex:

- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex
{
  NSRange result = NSNotFoundRange, range = NSMaxiumRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions, 0L,      self, &range, NULL, NULL,  &result, 0UL, NULL, NULL);
  return(result);
}

- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex capture:(NSInteger)capture
{
  NSRange result = NSNotFoundRange, range = NSMaxiumRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions, capture, self, &range, NULL, NULL,  &result, 0UL, NULL, NULL);
  return(result);
}

- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex inRange:(NSRange)range
{
  NSRange result = NSNotFoundRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions, 0L,      self, &range, NULL, NULL,  &result, 0UL, NULL, NULL);
  return(result);
}

- (NSRange)RKL_METHOD_PREPEND(rangeOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range capture:(NSInteger)capture error:(NSError **)error
{
  NSRange result = NSNotFoundRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, options,      capture, self, &range, NULL, error, &result, 0UL, NULL, NULL);
  return(result);
}

#pragma mark -stringByMatching:

- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex
{
  NSRange matchedRange = NSNotFoundRange, range = NSMaxiumRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions,      0L,      self, &range, NULL, NULL,  &matchedRange, 0UL, NULL, NULL);
  return((matchedRange.location == (NSUInteger)NSNotFound) ? NULL : rkl_CFAutorelease(CFStringCreateWithSubstring(NULL, (CFStringRef)self, CFMakeRange(matchedRange.location, matchedRange.length)))); // Warning about potential leak can be safely ignored.
} // Warning about potential leak can be safely ignored.

- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex capture:(NSInteger)capture
{
  NSRange matchedRange = NSNotFoundRange, range = NSMaxiumRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions,      capture, self, &range, NULL, NULL,  &matchedRange, 0UL, NULL, NULL);
  return((matchedRange.location == (NSUInteger)NSNotFound) ? NULL : rkl_CFAutorelease(CFStringCreateWithSubstring(NULL, (CFStringRef)self, CFMakeRange(matchedRange.location, matchedRange.length)))); // Warning about potential leak can be safely ignored.
} // Warning about potential leak can be safely ignored.

- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex inRange:(NSRange)range
{
  NSRange matchedRange = NSNotFoundRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, RKLNoOptions,      0L,      self, &range, NULL, NULL,  &matchedRange, 0UL, NULL, NULL);
  return((matchedRange.location == (NSUInteger)NSNotFound) ? NULL : rkl_CFAutorelease(CFStringCreateWithSubstring(NULL, (CFStringRef)self, CFMakeRange(matchedRange.location, matchedRange.length)))); // Warning about potential leak can be safely ignored.
} // Warning about potential leak can be safely ignored.

- (NSString *)RKL_METHOD_PREPEND(stringByMatching):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range capture:(NSInteger)capture error:(NSError **)error
{
  NSRange matchedRange = NSNotFoundRange;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLRangeOp, regex, options,           capture, self, &range, NULL, error, &matchedRange, 0UL, NULL, NULL);
  return((matchedRange.location == (NSUInteger)NSNotFound) ? NULL : rkl_CFAutorelease(CFStringCreateWithSubstring(NULL, (CFStringRef)self, CFMakeRange(matchedRange.location, matchedRange.length)))); // Warning about potential leak can be safely ignored.
} // Warning about potential leak can be safely ignored.

#pragma mark -stringByReplacingOccurrencesOfRegex:

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement
{
  NSRange searchRange = NSMaxiumRange;
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLReplaceOp, regex, RKLNoOptions, 0L, self, &searchRange, replacement, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement range:(NSRange)searchRange
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLReplaceOp, regex, RKLNoOptions, 0L, self, &searchRange, replacement, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement options:(RKLRegexOptions)options range:(NSRange)searchRange error:(NSError **)error
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLReplaceOp, regex, options,      0L, self, &searchRange, replacement, error, NULL, 0UL, NULL, NULL));
}

#pragma mark -componentsMatchedByRegex:

- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex
{
  NSRange searchRange = NSMaxiumRange;
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLArrayOfStringsOp, regex, RKLNoOptions, 0L,      self, &searchRange, NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex capture:(NSInteger)capture
{
  NSRange searchRange = NSMaxiumRange;
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLArrayOfStringsOp, regex, RKLNoOptions, capture, self, &searchRange, NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex range:(NSRange)range
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLArrayOfStringsOp, regex, RKLNoOptions, 0L,      self, &range,       NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(componentsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range capture:(NSInteger)capture error:(NSError **)error
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLArrayOfStringsOp, regex, options,      capture, self, &range,       NULL, error, NULL, 0UL, NULL, NULL));
}

#pragma mark -captureComponentsMatchedByRegex:

- (NSArray *)RKL_METHOD_PREPEND(captureComponentsMatchedByRegex):(NSString *)regex
{
  NSRange searchRange = NSMaxiumRange;
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, RKLNoOptions, 0L, self, &searchRange, NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(captureComponentsMatchedByRegex):(NSString *)regex range:(NSRange)range
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, RKLNoOptions, 0L, self, &range,       NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(captureComponentsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, options,      0L, self, &range,       NULL, error, NULL, 0UL, NULL, NULL));
}

#pragma mark -arrayOfCaptureComponentsMatchedByRegex:

- (NSArray *)RKL_METHOD_PREPEND(arrayOfCaptureComponentsMatchedByRegex):(NSString *)regex
{
  NSRange searchRange = NSMaxiumRange;
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)(RKLArrayOfCapturesOp | RKLSubcapturesArray), regex, RKLNoOptions, 0L, self, &searchRange, NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(arrayOfCaptureComponentsMatchedByRegex):(NSString *)regex range:(NSRange)range
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)(RKLArrayOfCapturesOp | RKLSubcapturesArray), regex, RKLNoOptions, 0L, self, &range,       NULL, NULL,  NULL, 0UL, NULL, NULL));
}

- (NSArray *)RKL_METHOD_PREPEND(arrayOfCaptureComponentsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)(RKLArrayOfCapturesOp | RKLSubcapturesArray), regex, options,      0L, self, &range,       NULL, error, NULL, 0UL, NULL, NULL));
}

#pragma mark -dictionaryByMatchingRegex:

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex withKeysAndCaptures:(id)firstKey, ...
{
  NSRange searchRange  = NSMaxiumRange;
  id      returnObject = NULL;
  va_list varArgsList;
  va_start(varArgsList, firstKey);
  returnObject = rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLDictionaryOfCapturesOp, regex, (RKLRegexOptions)RKLNoOptions, 0L, self, &searchRange, NULL, NULL, NULL, firstKey, varArgsList);
  va_end(varArgsList);
  return(returnObject);
}

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex range:(NSRange)range withKeysAndCaptures:(id)firstKey, ...
{
  id returnObject = NULL;
  va_list varArgsList;
  va_start(varArgsList, firstKey);
  returnObject = rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLDictionaryOfCapturesOp, regex, (RKLRegexOptions)RKLNoOptions, 0L, self, &range, NULL, NULL, NULL, firstKey, varArgsList);
  va_end(varArgsList);
  return(returnObject);
}

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeysAndCaptures:(id)firstKey, ...
{
  id returnObject = NULL;
  va_list varArgsList;
  va_start(varArgsList, firstKey);
  returnObject = rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLDictionaryOfCapturesOp, regex, options, 0L, self, &range, NULL, error, NULL, firstKey, varArgsList);
  va_end(varArgsList);
  return(returnObject);
}

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withFirstKey:(id)firstKey arguments:(va_list)varArgsList
{
  return(rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLDictionaryOfCapturesOp, regex, options, 0L, self, &range, NULL, error, NULL, firstKey, varArgsList));
}

- (NSDictionary *)RKL_METHOD_PREPEND(dictionaryByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeys:(id *)keys forCaptures:(int *)captures count:(NSUInteger)count
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLDictionaryOfCapturesOp, regex, options, 0L, self, &range, NULL, error, NULL, count, keys, captures));
}

#pragma mark -arrayOfDictionariesByMatchingRegex:

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex withKeysAndCaptures:(id)firstKey, ...
{
  NSRange searchRange  = NSMaxiumRange;
  id      returnObject = NULL;
  va_list varArgsList;
  va_start(varArgsList, firstKey);
  returnObject = rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLArrayOfDictionariesOfCapturesOp, regex, (RKLRegexOptions)RKLNoOptions, 0L, self, &searchRange, NULL, NULL, NULL, firstKey, varArgsList);
  va_end(varArgsList);
  return(returnObject);
}

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex range:(NSRange)range withKeysAndCaptures:(id)firstKey, ...
{
  id returnObject = NULL;
  va_list varArgsList;
  va_start(varArgsList, firstKey);
  returnObject = rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLArrayOfDictionariesOfCapturesOp, regex, (RKLRegexOptions)RKLNoOptions, 0L, self, &range, NULL, NULL, NULL, firstKey, varArgsList);
  va_end(varArgsList);
  return(returnObject);
}

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeysAndCaptures:(id)firstKey, ...
{
  id returnObject = NULL;
  va_list varArgsList;
  va_start(varArgsList, firstKey);
  returnObject = rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLArrayOfDictionariesOfCapturesOp, regex, options, 0L, self, &range, NULL, error, NULL, firstKey, varArgsList);
  va_end(varArgsList);
  return(returnObject);
}

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withFirstKey:(id)firstKey arguments:(va_list)varArgsList
{
  return(rkl_performDictionaryVarArgsOp(self, _cmd, (RKLRegexOp)RKLArrayOfDictionariesOfCapturesOp, regex, options, 0L, self, &range, NULL, error, NULL, firstKey, varArgsList));
}

- (NSArray *)RKL_METHOD_PREPEND(arrayOfDictionariesByMatchingRegex):(NSString *)regex options:(RKLRegexOptions)options range:(NSRange)range error:(NSError **)error withKeys:(id *)keys forCaptures:(int *)captures count:(NSUInteger)count
{
  return(rkl_performRegexOp(self, _cmd, (RKLRegexOp)RKLArrayOfDictionariesOfCapturesOp, regex, options, 0L, self, &range, NULL, error, NULL, count, keys, captures));
}

#ifdef    _RKL_BLOCKS_ENABLED

////////////
#pragma mark -
#pragma mark ^Blocks Related NSString Methods

#pragma mark -enumerateStringsMatchedByRegex:usingBlock:

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsMatchedByRegex):(NSString *)regex usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  NSUInteger errorFree = NO;
  rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, (RKLRegexOptions)RKLNoOptions, self, NSMaxiumRange, (RKLBlockEnumerationOp)RKLBlockEnumerationMatchOp, 0UL,                NULL, &errorFree, NULL,  block, NULL);
  return(errorFree == NO ? NO : YES);
}

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsMatchedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  NSUInteger errorFree = NO;
  rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, options,                       self, range,         (RKLBlockEnumerationOp)RKLBlockEnumerationMatchOp, enumerationOptions, NULL, &errorFree, error, block, NULL);
  return(errorFree == NO ? NO : YES);
}

#pragma mark -enumerateStringsSeparatedByRegex:usingBlock:

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsSeparatedByRegex):(NSString *)regex usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  NSUInteger errorFree = NO;
  rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLSplitOp,         regex, (RKLRegexOptions)RKLNoOptions, self, NSMaxiumRange, (RKLBlockEnumerationOp)RKLBlockEnumerationMatchOp, 0UL,                NULL, &errorFree, NULL,  block, NULL);
  return(errorFree == NO ? NO : YES);
}

- (BOOL)RKL_METHOD_PREPEND(enumerateStringsSeparatedByRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(void (^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  NSUInteger errorFree = NO;
  rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLSplitOp,         regex, options,                       self, range,         (RKLBlockEnumerationOp)RKLBlockEnumerationMatchOp, enumerationOptions, NULL, &errorFree, error, block, NULL);
  return(errorFree == NO ? NO : YES);  
}

#pragma mark -stringByReplacingOccurrencesOfRegex:usingBlock:

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  return(rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, (RKLRegexOptions)RKLNoOptions, self, NSMaxiumRange, (RKLBlockEnumerationOp)RKLBlockEnumerationReplaceOp, 0UL,                NULL, NULL, NULL,  NULL, block));
}

- (NSString *)RKL_METHOD_PREPEND(stringByReplacingOccurrencesOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  return(rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, options,                       self, range,         (RKLBlockEnumerationOp)RKLBlockEnumerationReplaceOp, enumerationOptions, NULL, NULL, error, NULL, block));
}

#endif // _RKL_BLOCKS_ENABLED

@end

////////////
#pragma mark -
@implementation NSMutableString (RegexKitLiteAdditions)

#pragma mark -replaceOccurrencesOfRegex:

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement
{
  NSRange    searchRange   = NSMaxiumRange;
  NSInteger replacedCount = -1L;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)(RKLReplaceOp | RKLReplaceMutable), regex, RKLNoOptions, 0L, self, &searchRange, replacement, NULL,  (void **)((void *)&replacedCount), 0UL, NULL, NULL);
  return(replacedCount);
}

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement range:(NSRange)searchRange
{
  NSInteger replacedCount = -1L;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)(RKLReplaceOp | RKLReplaceMutable), regex, RKLNoOptions, 0L, self, &searchRange, replacement, NULL,  (void **)((void *)&replacedCount), 0UL, NULL, NULL);
  return(replacedCount);
}

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex withString:(NSString *)replacement options:(RKLRegexOptions)options range:(NSRange)searchRange error:(NSError **)error
{
  NSInteger replacedCount = -1L;
  rkl_performRegexOp(self, _cmd, (RKLRegexOp)(RKLReplaceOp | RKLReplaceMutable), regex, options,      0L, self, &searchRange, replacement, error, (void **)((void *)&replacedCount), 0UL, NULL, NULL);
  return(replacedCount);
}

#ifdef    _RKL_BLOCKS_ENABLED

////////////
#pragma mark -
#pragma mark ^Blocks Related NSMutableString Methods

#pragma mark -replaceOccurrencesOfRegex:usingBlock:

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  NSUInteger errorFree     = 0UL;
  NSInteger replacedCount  = -1L;
  NSString *replacedString = rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, RKLNoOptions, self, NSMaxiumRange, (RKLBlockEnumerationOp)RKLBlockEnumerationReplaceOp, 0UL,                &replacedCount, &errorFree, NULL,  NULL, block);
  if((errorFree == YES) && (replacedCount > 0L)) { [self replaceCharactersInRange:NSMakeRange(0UL, [self length]) withString:replacedString]; }
  return(replacedCount);
}

- (NSInteger)RKL_METHOD_PREPEND(replaceOccurrencesOfRegex):(NSString *)regex options:(RKLRegexOptions)options inRange:(NSRange)range error:(NSError **)error enumerationOptions:(RKLRegexEnumerationOptions)enumerationOptions usingBlock:(NSString *(^)(NSInteger captureCount, NSString * const capturedStrings[captureCount], const NSRange capturedRanges[captureCount], volatile BOOL * const stop))block
{
  NSUInteger errorFree     = 0UL;
  NSInteger replacedCount  = -1L;
  NSString *replacedString = rkl_performEnumerationUsingBlock(self, _cmd, (RKLRegexOp)RKLCapturesArrayOp, regex, options,      self, range,         (RKLBlockEnumerationOp)RKLBlockEnumerationReplaceOp, enumerationOptions, &replacedCount, &errorFree, error, NULL, block);
  if((errorFree == YES) && (replacedCount > 0L)) { [self replaceCharactersInRange:range withString:replacedString]; }
  return(replacedCount);
}

#endif // _RKL_BLOCKS_ENABLED

@end
