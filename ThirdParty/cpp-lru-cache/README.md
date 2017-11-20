cpp-lru-cache
=============

Simple and reliable LRU (Least Recently Used) cache for c++ based on hashmap and linkedlist. The library is header only, simple test and example are included.
It includes standard components and very little own logics that guarantees reliability.

Example:

```
/**Creates cache with maximum size of three. When the 
   size in achieved every next element will replace the 
   least recently used one */
cache::lru_cache<std::string, std::string> cache(3);

cache.put("one", "one");
cache.put("two", "two");

const std::string& from_cache = cache.get("two")

```

How to run tests:

```
mkdir build
cd build
cmake ..
make check
```
