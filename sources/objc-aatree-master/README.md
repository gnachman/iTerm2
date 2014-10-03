## Description

This is an implementation of the Arne Andersson Tree, which is a *balanced binary search tree*. In short, that means *fast* look-up times to objects! For more information on how the balancing, inserting and deletion algorithms work, see [wikipedia](http://en.wikipedia.org/wiki/Andersson_tree.) 

This class is an extension of the `NSMutableDictionary` class cluster, so all of the methods you've come to expect from the Foundation Collections (and mainly in the `NSMutableDictionary` public abstract interface) can be called on this class as well, with the exception of the initialize methods. The class supports, among others, the `NSCopying` and `NSFastEnumeration` protocols. 

The tree is completely *thread safe*. It uses a readers/write lock pattern, so multiple readers (threads) don't lock each other out. The only time the readers do get locked is when a writer (thread) wants or has access to the tree for mutations. In short, the accessors can be used in parallel, but will have to wait for possible mutations to finish. This thread safety pattern is very suitable for a tree like this and is, compared to the other locking mechanisms in Objective-C, the fastest pattern when the tree is accessed more often than it is mutated in a threaded environment. 

One of the big advantages of using a tree as data model, apart from fast look-up times, is that it is easy to determine an object closest to a key. This is why the method `objectClosestToKey:` is included in the interface. 

The class is suitable for *any type of data*, and more importantly, for any type of key. When initializing the tree, a `NSComparator` block is specified, which contains the logic to compare two keys. A copy of the key is created when inserted into the tree, so it must implement the `NSCopying` protocol. 

## Requirements

This class requires Mac OS X v10.6, since it uses blocks. 

## Usage 

Download the latest revision from the downloads or check out the source to get started. See the [Usage](https://github.com/aroemers/objc-aatree/wiki/Usage) wiki page for how to use it in your source code. 


Code license: New BSD License 

Labels: ObjC, Objective-C, ObjectiveC, Objective, C, Balanced, Binary, Search, Tree, Arne, Andersson, AATree, NSDictionary
