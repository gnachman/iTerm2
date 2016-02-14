//
//  JGMethodSwizzler.h
//  JGMethodSwizzler
//
//  Created by Jonas Gessner 22.08.2013
//  Copyright (c) 2013 Jonas Gessner. All rights reserved.
//

#import <Foundation/Foundation.h>



//-------------
/* typedefs */
//-------------

typedef void *(* JG_IMP)(__unsafe_unretained id, SEL, ...);

typedef id (^JGMethodReplacementProvider)(JG_IMP original, __unsafe_unretained Class swizzledClass, SEL selector);





//----------------
/* Deswizzling */
//----------------

/**
 Deswizzle all methods that have been swizzled accross all instances.
 
 @return \c YES if any methods have been deswizzled successfully.
 */

OBJC_EXTERN BOOL deswizzleGlobal(void);


/**
 Deswizzle all methods that have been swizzled for specific instances.
 
 @return \c YES if any methods have been deswizzled successfully.
 */

OBJC_EXTERN BOOL deswizzleInstances(void);


/**
 Deswizzle all methods.
 
 @return \c YES if any methods have been deswizzled successfully.
 */

OBJC_EXTERN BOOL deswizzleAll(void);


//-----------------
/* Helper macros */
//-----------------

#define JGMethodReplacement(returntype, selftype, ...) ^ returntype (__unsafe_unretained selftype self, ##__VA_ARGS__)
#define JGMethodReplacementProviderBlock ^ id (JG_IMP original, __unsafe_unretained Class swizzledClass, SEL _cmd)
#define JGOriginalImplementation(type, ...) ((__typeof(type (*)(__typeof(self), SEL, ...)))original)(self, _cmd, ##__VA_ARGS__)



//---------------------------------------
/** @name Super easy method swizzling */
//---------------------------------------

@interface NSObject (JGMethodSwizzler)


/**
 Swizzle the specified class method.
 
 @param selector Selector of the method to swizzle.
 @param replacement The replacement block to use for swizzling the method. Its signature needs to be: return_type ^(id self, ...).
 
 */

+ (void)swizzleClassMethod:(SEL)selector withReplacement:(JGMethodReplacementProvider)replacementProvider;


/**
 Swizzle the specified instance method.
 
 @param selector Selector of the method to swizzle.
 @param replacement The replacement block to use for swizzling the method. Its signature needs to be: return_type ^(id self, ...).
 
 */

+ (void)swizzleInstanceMethod:(SEL)selector withReplacement:(JGMethodReplacementProvider)replacementProvider;

@end




//---------------------------------------
/** @name Super easy method swizzling */
//---------------------------------------

@interface NSObject (JGMethodDeSwizzler)

/**
 Restore the specified class method by removing all swizzles.
 
 @param selector Selector of the swizzled method.
 
 @return \c YES if the method was successfully restored, \c NO if the method has never been swizzled.
 
 */

+ (BOOL)deswizzleClassMethod:(SEL)selector;




/**
 Restore the specified class method by removing all swizzles.
 
 @param selector Selector of the swizzled method.
 
 @return \c YES if the method was successfully restored, \c NO if the method has never been swizzled.
 
 */

+ (BOOL)deswizzleInstanceMethod:(SEL)selector;





/**
 Restore all swizzled class methods.
 
 @return \c YES if the method was successfully restored, \c NO if no method has never been swizzled
 
 */

+ (BOOL)deswizzleAllClassMethods;



/**
 Restore all swizzled instance methods.
 
 @return \c YES if the method was successfully restored, \c NO if no method has never been swizzled.
 
 */

+ (BOOL)deswizzleAllInstanceMethods;




/**
 Restore all swizzled class and instance methods.
 
 @return \c YES if the method was successfully restored, \c NO if no method has never been swizzled.
 
 */

+ (BOOL)deswizzleAllMethods;

@end






//-------------------------------------------------------------
/** @name Super easy method swizzling on specific instances */
//-------------------------------------------------------------


@interface NSObject (JGInstanceSwizzler)

/**
 Swizzle the specified instance method on this specific instance only.
 
 @param selector Selector of the method to swizzle.
 @param replacement The replacement block to use for swizzling the method. Its signature needs to be: return_type ^(id self, ...).
 
 */
- (void)swizzleMethod:(SEL)selector withReplacement:(JGMethodReplacementProvider)replacementProvider;



/**
 Restore the specified method by removing all swizzles.
 
 @param selector Selector of the swizzled method.
 
 @return \c YES if the method was successfully restored, \c NO if the method has never been swizzled.
 
 */

- (BOOL)deswizzleMethod:(SEL)selector;



/**
 Restore all swizzled methods.
 
 @return \c YES if the method was successfully restored, \c NO if no method has never been swizzled.
 
 */

- (BOOL)deswizzle;


@end


