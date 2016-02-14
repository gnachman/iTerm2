<h1>JGMethodSwizzler</h1><h6>© 2013-2014 Jonas Gessner</h6>

----------------
<br>

An easy to use Objective-C API for swizzling class and instance methods, as well as swizzling instance methods on specific instances only.

Setup
=====
<b>CocoaPods:</b><br>
Add this to your `Podfile`:
```
pod 'JGMethodSwizzler', '2.0.1'
```
<p>
OR:
<p>
<b>Add source Files:</b><br>
1. Add the `JGMethodSwizzler` folder to your Xcode Project.<br>
2. `#import "JGMethodSwizzler.h"`.

Documentation
=============
#####For further examples see the `JGMethodSwizzlerTests` Xcode project.


JGMethodSwizzler can be used for three basic swizzling types: Swizzling a specific method for all instances of a class, swizzling class methods and swizzling instance methods of specific instances only.

JGMethodSwizzler is completely thread safe and can handle multiple swizzles. Instance-specific swizzling should however not be combined with global swizzling in the same method.



###Swizzling a class method:
Swizzling the method `+(int)[TestClass test:(int)]`
```objc
[TestClass swizzleClassMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
	//return a replacement block
	return JGMethodReplacement(int, const Class *, int arg) {
		//get the original value
		int orig = JGOriginalImplementation(int, arg);
		//return the modified value
		return orig+2;
	};
}];
```

After this code is run, calling the method will return the modified value until the method is deswizzled.


###Swizzling an instance method across all instances of a class:
Swizzling the method `-(int)[TestClass test:(int)]`
```objc
[TestClass swizzleInstanceMethod:@selector(test:) withReplacement:JGMethodReplacementProviderBlock {
	//return a replacement block
	return JGMethodReplacement(int, TestClass *, int arg) {
		//get the original value
		int orig = JGOriginalImplementation(int, arg);
		//return the modified value
		return orig+2;
	};
}];
```

After this code is run, calling the method will return the modified value until the method is deswizzled.



###Swizzling an instance method for a specific instance:
Swizzling the `description` method on a specific `NSObject`instance:
```objc
NSObject *object = [NSObject new];

[object swizzleMethod:@selector(description) withReplacement:JGMethodReplacementProviderBlock {
	return JGMethodReplacement(NSString *, NSObject *) {
		NSString *orig = JGOriginalImplementation(NSString *);
            
		return [orig stringByAppendingString:@" Swizzled!!"];
	};
}];
```

After this code is run, calling the method will return the modified value until the method is deswizzled.


###Deswizzling

All swizzles can be removed once they've been applied.


`deswizzleAll()` removes all swizzles.


####Deswizzling global class and instance swizzles

`deswizzleGlobal()` removes all swizzles that have been applied as global swizzles (not instance specific).

`+deswizzleClassMethod:(SEL)` deswizzles a specific class method.

`+deswizzleInstanceMethod:(SEL)` deswizzles a specific instance method.

`+deswizzleAllClassMethods` deswizzles all swizzled class methods of this class.

`+deswizzleAllInstanceMethods` deswizzles all swizzled instance methods of this class.

`+deswizzleAllMethods` deswizzles all swizzled methods of this class.


####Deswizzling Instance specific swizzles

`deswizzleInstances()` removes all swizzles that have been applied as instance specific swizzles.

`-deswizzleMethod:(SEL)` deswizzles a specific instance method of this instance.

`-deswizzle` deswizzles all swizzled instance methods of this instance.


Notes
=======
`JGMethodSwizzler` works with both ARC and MRC/MRR.

Credits
=========
Created by Jonas Gessner. ©2013-2014

Thanks to Andrew Richardson for his inspiration and contribution with `InstanceHook`.

License
==========
Licensed under the MIT license.
