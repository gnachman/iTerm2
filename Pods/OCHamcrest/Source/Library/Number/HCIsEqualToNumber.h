//
//  OCHamcrest - HCIsEqualToNumber.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import <OCHamcrest/HCBaseMatcher.h>


OBJC_EXPORT id<HCMatcher> HC_equalToBool(BOOL value);

/**
    equalToBool(value) -
    Matches if object is equal to @c NSNumber created from a @c BOOL.

    @param value  The @c BOOL value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c BOOL @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToBool instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToBool HC_equalToBool
#endif

@interface HCIsEqualToBool : HCBaseMatcher

- (id)initWithValue:(BOOL)value;

@end


OBJC_EXPORT id<HCMatcher> HC_equalToChar(char value);

/**
    equalToChar(value) -
    Matches if object is equal to @c NSNumber created from a @c char.

    @param value  The @c char value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c char @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToChar instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToChar HC_equalToChar
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToDouble(double value);

/**
    equalToDouble(value) -
    Matches if object is equal to @c NSNumber created from a @c double.

    @param value  The @c double value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c double @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToDouble instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToDouble HC_equalToDouble
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToFloat(float value);

/**
    equalToFloat(value) -
    Matches if object is equal to @c NSNumber created from a @c float.

    @param value  The @c float value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c float @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToFloat instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToFloat HC_equalToFloat
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToInt(int value);

/**
    equalToInt(value) -
    Matches if object is equal to @c NSNumber created from an @c int.

    @param value  The @c int value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c int @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToInt instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToInt HC_equalToInt
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToLong(long value);

/**
    equalToLong(value) -
    Matches if object is equal to @c NSNumber created from a @c long.

    @param value  The @c long value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c long @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToLong instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToLong HC_equalToLong
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToLongLong(long long value);

/**
    equalToLongLong(value) -
    Matches if object is equal to @c NSNumber created from a <code>long long</code>.

    @param value  The <code>long long</code> value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a <code>long long</code> @a value and compares
    the evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToLongLong instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToLongLong HC_equalToLongLong
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToShort(short value);

/**
    equalToShort(value) -
    Matches if object is equal to @c NSNumber created from a @c short.

    @param value  The @c short value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from a @c short @a value and compares the evaluated
    object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToShort instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToShort HC_equalToShort
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToUnsignedChar(unsigned char value);

/**
    equalToUnsignedChar(value) -
    Matches if object is equal to @c NSNumber created from an <code>unsigned char</code>.

    @param value  The <code>unsigned char</code> value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an <code>unsigned char</code> @a value and
    compares the evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToUnsignedChar instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToUnsignedChar HC_equalToUnsignedChar
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToUnsignedInt(unsigned int value);

/**
    equalToUnsignedInt(value) -
    Matches if object is equal to @c NSNumber created from an <code>unsigned int</code>.

    @param value  The <code>unsigned int</code> value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an <code>unsigned int</code> @a value and
    compares the evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToUnsignedInt instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToUnsignedInt HC_equalToUnsignedInt
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToUnsignedLong(unsigned long value);

/**
    equalToUnsignedLong(value) -
    Matches if object is equal to @c NSNumber created from an <code>unsigned long</code>.

    @param value  The <code>unsigned long</code> value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an <code>unsigned long</code> @a value and
    compares the evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToUnsignedLong instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToUnsignedLong HC_equalToUnsignedLong
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToUnsignedLongLong(unsigned long long value);

/**
    equalToUnsignedLongLong(value) -
    Matches if object is equal to @c NSNumber created from an <code>unsigned long long</code>.

    @param value  The <code>unsigned long long</code> value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an <code>unsigned long long</code> @a value and
    compares the evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToUnsignedLongLong instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToUnsignedLongLong HC_equalToUnsignedLongLong
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToUnsignedShort(unsigned short value);

/**
    equalToUnsignedShort(value) -
    Matches if object is equal to @c NSNumber created from an <code>unsigned short</code>.

    @param value  The <code>unsigned short</code> value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an <code>unsigned short</code> @a value and
    compares the evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToUnsignedShort instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToUnsignedShort HC_equalToUnsignedShort
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToInteger(NSInteger value);

/**
    equalToInteger(value) -
    Matches if object is equal to @c NSNumber created from an @c NSInteger.

    @param value  The @c NSInteger value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an @c NSInteger @a value and compares the
    evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToInteger instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToInteger HC_equalToInteger
#endif


OBJC_EXPORT id<HCMatcher> HC_equalToUnsignedInteger(NSUInteger value);

/**
    equalToUnsignedInteger(value) -
    Matches if object is equal to @c NSNumber created from an @c NSUInteger.

    @param value  The @c NSUInteger value from which to create an @c NSNumber.

    This matcher creates an @c NSNumber object from an @c NSUInteger @a value and compares the
    evaluated object to it for equality.

    (In the event of a name clash, don't \#define @c HC_SHORTHAND and use the synonym
    @c HC_equalToUnsignedInteger instead.)

    @ingroup primitive_number_matchers
 */
#ifdef HC_SHORTHAND
    #define equalToUnsignedInteger HC_equalToUnsignedInteger
#endif
