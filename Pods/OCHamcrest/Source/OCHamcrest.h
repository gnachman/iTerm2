//
//  OCHamcrest - OCHamcrest.h
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

/**
    @defgroup library Matcher Library

    Library of Matcher implementations.
 */

/**
    @defgroup object_matchers Object Matchers

    Matchers that inspect objects.

    @ingroup library
 */
#import <OCHamcrest/HCConformsToProtocol.h>
#import <OCHamcrest/HCHasDescription.h>
#import <OCHamcrest/HCHasProperty.h>
#import <OCHamcrest/HCIsEqual.h>
#import <OCHamcrest/HCIsInstanceOf.h>
#import <OCHamcrest/HCIsNil.h>
#import <OCHamcrest/HCIsSame.h>
#import <OCHamcrest/HCIsTypeOf.h>

/**
    @defgroup collection_matchers Collection Matchers

    Matchers of collections.

    @ingroup library
 */
#import <OCHamcrest/HCHasCount.h>
#import <OCHamcrest/HCIsCollectionContaining.h>
#import <OCHamcrest/HCIsCollectionContainingInAnyOrder.h>
#import <OCHamcrest/HCIsCollectionContainingInOrder.h>
#import <OCHamcrest/HCIsCollectionOnlyContaining.h>
#import <OCHamcrest/HCIsDictionaryContaining.h>
#import <OCHamcrest/HCIsDictionaryContainingEntries.h>
#import <OCHamcrest/HCIsDictionaryContainingKey.h>
#import <OCHamcrest/HCIsDictionaryContainingValue.h>
#import <OCHamcrest/HCIsEmptyCollection.h>
#import <OCHamcrest/HCIsIn.h>

/**
    @defgroup number_matchers Number Matchers

    Matchers that perform numeric comparisons.

    @ingroup library
 */
#import <OCHamcrest/HCIsCloseTo.h>
#import <OCHamcrest/HCOrderingComparison.h>

/**
    @defgroup primitive_number_matchers Primitive Number Matchers

    Matchers for testing equality against primitive numeric types.

    @ingroup number_matchers
 */
#import <OCHamcrest/HCIsEqualToNumber.h>

/**
    @defgroup text_matchers Text Matchers

    Matchers that perform text comparisons.

    @ingroup library
 */
#import <OCHamcrest/HCIsEqualIgnoringCase.h>
#import <OCHamcrest/HCIsEqualIgnoringWhiteSpace.h>
#import <OCHamcrest/HCStringContains.h>
#import <OCHamcrest/HCStringContainsInOrder.h>
#import <OCHamcrest/HCStringEndsWith.h>
#import <OCHamcrest/HCStringStartsWith.h>

/**
    @defgroup logical_matchers Logical Matchers

    Boolean logic using other matchers.

    @ingroup library
 */
#import <OCHamcrest/HCAllOf.h>
#import <OCHamcrest/HCAnyOf.h>
#import <OCHamcrest/HCIsAnything.h>
#import <OCHamcrest/HCIsNot.h>

/**
    @defgroup decorator_matchers Decorator Matchers

    Matchers that decorate other matchers for better expression.

    @ingroup library
 */
#import <OCHamcrest/HCDescribedAs.h>
#import <OCHamcrest/HCIs.h>

/**
    @defgroup integration Unit Test Integration
 */
#import <OCHamcrest/HCAssertThat.h>

/**
    @defgroup integration_numeric Unit Tests of Primitive Numbers

    Unit test integration for primitive numbers.

    The @c assertThat&lt;Type&gt; macros convert the primitive actual value to an @c NSNumber,
    passing that to the matcher for evaluation. If the matcher is not satisfied, an exception is
    thrown describing the mismatch.

    This family of macros is designed to integrate well with OCUnit and other unit testing
    frameworks. Unmet assertions are reported as test failures. In Xcode, they can be clicked to
    reveal the line of the assertion.

    @ingroup integration
 */
#import <OCHamcrest/HCNumberAssert.h>

/**
    @defgroup core Core API
 */

/**
    @defgroup helpers Helpers

    Utilities for writing Matchers.

    @ingroup core
 */
