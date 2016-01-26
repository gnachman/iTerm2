//
//  OCHamcrest - HCNumberAssert.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <Foundation/Foundation.h>

@protocol HCMatcher;


OBJC_EXPORT void HC_assertThatBoolWithLocation(id testCase, BOOL actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatBool(actual, matcher)  \
    HC_assertThatBoolWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatBool(actual, matcher) -
    Asserts that @c BOOL actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c BOOL value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatBool instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatBool HC_assertThatBool
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatCharWithLocation(id testCase, char actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatChar(actual, matcher)  \
    HC_assertThatCharWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatChar(actual, matcher) -
    Asserts that @c char actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c char value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatChar instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatChar HC_assertThatChar
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatDoubleWithLocation(id testCase, double actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatDouble(actual, matcher)  \
    HC_assertThatDoubleWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    HC_assertThatDouble(actual, matcher) -
    Asserts that @c double actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c double value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatDouble instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatDouble HC_assertThatDouble
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatFloatWithLocation(id testCase, float actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatFloat(actual, matcher)  \
    HC_assertThatFloatWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatFloat(actual, matcher) -
    Asserts that @c float actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c float value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatFloat instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatFloat HC_assertThatFloat
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatIntWithLocation(id testCase, int actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatInt(actual, matcher)  \
    HC_assertThatIntWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatInt(actual, matcher) -
    Asserts that @c int actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c int value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatInt instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatInt HC_assertThatInt
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatLongWithLocation(id testCase, long actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatLong(actual, matcher)  \
    HC_assertThatLongWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatLong(actual, matcher) -
    Asserts that @c long actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c long value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatLong instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatLong HC_assertThatLong
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatLongLongWithLocation(id testCase, long long actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatLongLong(actual, matcher)  \
    HC_assertThatLongLongWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatLongLong(actual, matcher) -
    Asserts that <code>long long</code> actual value, converted to an @c NSNumber, satisfies
    matcher.

    @param actual   The <code>long long</code> value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatLongLong instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatLongLong HC_assertThatLongLong
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatShortWithLocation(id testCase, short actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatShort(actual, matcher)  \
    HC_assertThatShortWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatShort(actual, matcher) -
    Asserts that @c short actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c short value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatShort instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatShort HC_assertThatShort
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatUnsignedCharWithLocation(id testCase, unsigned char actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatUnsignedChar(actual, matcher)  \
    HC_assertThatUnsignedCharWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatUnsignedChar(actual, matcher) -
    Asserts that <code>unsigned char</code> actual value, converted to an @c NSNumber, satisfies
    matcher.

    @param actual   The <code>unsigned char</code> value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatUnsignedChar instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatUnsignedChar HC_assertThatUnsignedChar
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatUnsignedIntWithLocation(id testCase, unsigned int actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatUnsignedInt(actual, matcher)  \
    HC_assertThatUnsignedIntWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatUnsignedInt(actual, matcher) -
    Asserts that <code>unsigned int</code> actual value, converted to an @c NSNumber, satisfies
    matcher.

    @param actual   The <code>unsigned int</code> value to convert to an @c NSNumber for evaluation    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatUnsignedInt instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatUnsignedInt HC_assertThatUnsignedInt
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatUnsignedLongWithLocation(id testCase, unsigned long actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatUnsignedLong(actual, matcher)  \
    HC_assertThatUnsignedLongWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatUnsignedLong(actual, matcher) -
    Asserts that <code>unsigned long</code> actual value, converted to an @c NSNumber, satisfies
    matcher.

    @param actual   The <code>unsigned long</code> value to convert to an @c NSNumber for evaluation    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatUnsignedLong instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatUnsignedLong HC_assertThatUnsignedLong
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatUnsignedLongLongWithLocation(id testCase, unsigned long long actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatUnsignedLongLong(actual, matcher)  \
    HC_assertThatUnsignedLongLongWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatUnsignedLongLong(actual, matcher) -
    Asserts that <code>unsigned long long</code> actual value, converted to an @c NSNumber,
    satisfies matcher.

    @param actual   The <code>unsigned long long</code> value to convert to an @c NSNumber for evaluation    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatUnsignedLongLong instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatUnsignedLongLong HC_assertThatUnsignedLongLong
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatUnsignedShortWithLocation(id testCase, unsigned short actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatUnsignedShort(actual, matcher)  \
    HC_assertThatUnsignedShortWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatUnsignedShort(actual, matcher) -
    Asserts that <code>unsigned short</code> actual value, converted to an @c NSNumber, satisfies
    matcher.

    @param actual   The <code>unsigned short</code> value to convert to an @c NSNumber for evaluation    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatUnsignedShort instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatUnsignedShort HC_assertThatUnsignedShort
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatIntegerWithLocation(id testCase, NSInteger actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatInteger(actual, matcher)  \
    HC_assertThatIntegerWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatInteger(actual, matcher) -
    Asserts that @c NSInteger actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c NSInteger value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatInteger instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatInteger HC_assertThatInteger
#endif


#pragma mark -

OBJC_EXPORT void HC_assertThatUnsignedIntegerWithLocation(id testCase, NSUInteger actual,
        id<HCMatcher> matcher, const char* fileName, int lineNumber);

#define HC_assertThatUnsignedInteger(actual, matcher)  \
    HC_assertThatUnsignedIntegerWithLocation(self, actual, matcher, __FILE__, __LINE__)

/**
    assertThatUnsignedInteger(actual, matcher) -
    Asserts that @c NSUInteger actual value, converted to an @c NSNumber, satisfies matcher.

    @param actual   The @c NSUInteger value to convert to an @c NSNumber for evaluation.
    @param matcher  The matcher to satisfy as the expected condition.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_assertThatUnsignedInteger instead.)

    @ingroup integration_numeric
 */
#ifdef HC_SHORTHAND
    #define assertThatUnsignedInteger HC_assertThatUnsignedInteger
#endif
