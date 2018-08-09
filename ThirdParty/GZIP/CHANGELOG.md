# Change Log

## [1.2.1](https://github.com/nicklockwood/GZIP/releases/tag/1.2.1) (2017-07-03)

- Fixed incorrect case in header import

## [1.2](https://github.com/nicklockwood/GZIP/releases/tag/1.2) (2017-05-18)

- Removed dlopen, as Apple have begun rejecting apps that use it.
- Minimum deployment target is now iOS 8.0.
- Added watchOS / tvOS support.
- Added Carthage support.

## [1.1.1](https://github.com/nicklockwood/GZIP/releases/tag/1.1.1) (2015-07-24)

- Fixed crash on iOS 9.
- Added performance tests.

## [1.1](https://github.com/nicklockwood/GZIP/releases/tag/1.1) (2015-07-17)

- Added `isGzippedData` method.
- GZIP will no longer re-encode already-gzipped data, nor try  (and fail) to decode ungzipped data.
- GZIP now uses dlopen to load the libz.dylib at runtime, so there's no need to include it manually in your project.
- Fixed warnings and errors on Xcode 7

## [1.0.3](https://github.com/nicklockwood/GZIP/releases/tag/1.0.3) (2014-07-02)

- Fixed new warnings in Xcode 6
- Added Travis CI support

## [1.0.2](https://github.com/nicklockwood/GZIP/releases/tag/1.0.2) (2013-12-24)

- Now complies with -Weverything warning level

## [1.0.1](https://github.com/nicklockwood/GZIP/releases/tag/1.0.1) (2013-09-25)

- Added podspec
- Renamed source files
- Verified compliance with iOS 7 / Mac OS 10.8
- Verified compliance with -Wextra warning level


## [1.0](https://github.com/nicklockwood/GZIP/releases/tag/1.0) (2012-04-06)

- First release
