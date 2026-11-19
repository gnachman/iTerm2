# Shared settings for tools/swift_migration/sanitizer_tests.sh and
# tools/swift_migration/sanitizer_app.sh. Sourced, not run. See those
# scripts for documentation.

SAN_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAN_ROOT="$(cd "$SAN_HERE/../.." && pwd)"
SAN_IGNORELIST="$SAN_HERE/sanitizer_ignorelist.txt"
SAN_NULLABILITY_SUPPRESSIONS="$SAN_HERE/sanitizer_nullability_suppressions.txt"

# The ignore list's patterns (src:*/submodules/* and so on) match anywhere in
# the absolute path clang is given, so a checkout under a directory with one
# of those names would have every file exempted and the run would prove
# nothing. Fails (status 2) for such a checkout.
san_check_root_path() {
    case "$SAN_ROOT/" in
        */submodules/*|*/ThirdParty/*|*/Companion/*)
            echo "error: the checkout's path $SAN_ROOT has a directory named submodules, ThirdParty or Companion;" \
                "$SAN_IGNORELIST would exempt every file. Use a checkout elsewhere." >&2
            return 2 ;;
    esac
}

# The number of entries (lines that are neither blank nor comments) in $1.
san_count_entries() {
    grep -cvE '^[[:space:]]*(#|$)' "$1"
}

# The two clang groups of docs/swift-migration/phase0.md section 4.
SAN_NULLABILITY_GROUP="nullability"
SAN_INTEGER_GROUP="signed-integer-overflow,implicit-conversion,float-cast-overflow,integer-divide-by-zero,shift,bounds"

# The sign-change check of the integer-sign mode. Xcode's clang driver
# rejects -fsanitize=implicit-integer-sign-change for arm64 macOS, so the
# flags go to the compiler itself through -Xclang; its UBSan runtime handles
# the reports (the same handler as the truncation checks). Linking needs no
# flag of its own: -fsanitize=$SAN_INTEGER_GROUP links that runtime.
SAN_SIGN_CHANGE_CFLAGS="-Xclang -fsanitize=implicit-integer-sign-change -Xclang -fsanitize-recover=implicit-integer-sign-change"

# Options common to every UBSan run. report_error_type=1 makes the SUMMARY
# line name the check (for example signed-integer-overflow) instead of
# "undefined-behavior", which sanitizer_summary.py uses as the kind.
SAN_UBSAN_BASE_OPTIONS="print_stacktrace=1:report_error_type=1:print_summary=1:color=never"

# Settings every sanitizer build passes to xcodebuild, whatever the mode.
# $1 is the mode's build directory. Products and intermediates go there, never
# to Build/. SHARED_PRECOMPS_DIR must be set as well: in a scheme build it
# stays in Build/Intermediates.noindex/PrecompiledHeaders even when SYMROOT,
# OBJROOT and -derivedDataPath are all elsewhere. Index-while-building is
# off so Xcode's index store is not written. The address sanitizer, which the ModernTests test plan turns on, is
# turned off both as an xcodebuild option and as a build setting: a build
# setting on the command line outranks the test plan for every variant.
san_common_xcodebuild_args() {
    local build_dir="$1"
    SAN_XCODEBUILD_ARGS=(
        -project iTerm2.xcodeproj
        -configuration Development
        -destination 'platform=macOS'
        -skipPackagePluginValidation
        -enableAddressSanitizer NO
        -enableUndefinedBehaviorSanitizer NO
        ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES
        SYMROOT="$build_dir/Build"
        OBJROOT="$build_dir/Build/Intermediates.noindex"
        SHARED_PRECOMPS_DIR="$build_dir/Build/Intermediates.noindex/PrecompiledHeaders"
        COMPILER_INDEX_STORE_ENABLE=NO
        ENABLE_ADDRESS_SANITIZER=NO
        ENABLE_UNDEFINED_BEHAVIOR_SANITIZER=NO
    )
    # Signed or not exactly as tools/run_tests.expect does: unsigned unless
    # SIGNED=1.
    if [ "${SIGNED:-}" != "1" ]; then
        SAN_XCODEBUILD_ARGS+=(CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
    fi
}

# The same preparation `make Development` does for the string catalog, but
# the copy is made only when the content differs, so that the source's
# modification time does not change under the regular build in Build/.
san_prepare_catalog() {
    if ! cmp -s "$SAN_ROOT/xcstrings/Localizable.xcstrings" "$SAN_ROOT/sources/Localizable.xcstrings"; then
        cp -f "$SAN_ROOT/xcstrings/Localizable.xcstrings" "$SAN_ROOT/sources/Localizable.xcstrings"
    fi
}

# Prints the sanitizer runtimes the app at $1 links, or fails if it does not
# link the one named $2 (ubsan or tsan). A Development build puts the app's
# code in Contents/MacOS/iTerm2.debug.dylib (ENABLE_DEBUG_DYLIB) and the
# executable is a small stub, so the dylib is checked when there is one.
#
# otool's output is read whole into a variable before it is searched: piping
# it into `grep -q` under pipefail made the result depend on whether otool
# had finished writing when grep found its line (otool then died of SIGPIPE
# and the pipeline failed). The same holds for san_check_no_runtime.
san_check_runtime() {
    local app="$1" want="$2"
    local binary="$app/Contents/MacOS/iTerm2.debug.dylib"
    [ -f "$binary" ] || binary="$app/Contents/MacOS/iTerm2"
    local libraries
    if ! libraries="$(otool -L "$binary")"; then
        echo "error: otool -L $binary failed" >&2
        return 1
    fi
    case "$libraries" in
        *"libclang_rt.${want}_osx_dynamic"*) ;;
        *)
            echo "error: $binary does not link the $want runtime" >&2
            return 1 ;;
    esac
    echo "Runtime check: $(basename "$binary") links $(printf '%s\n' "$libraries" | grep -o "libclang_rt\.[a-z]*_osx_dynamic\.dylib" | sort -u | tr '\n' ' ')"
}

# Fails if the app at $1 links any sanitizer runtime (the plain mode).
san_check_no_runtime() {
    local app="$1"
    local binary="$app/Contents/MacOS/iTerm2.debug.dylib"
    [ -f "$binary" ] || binary="$app/Contents/MacOS/iTerm2"
    local libraries
    if ! libraries="$(otool -L "$binary")"; then
        echo "error: otool -L $binary failed" >&2
        return 1
    fi
    case "$libraries" in
        *"libclang_rt."*)
            echo "error: $binary links a sanitizer runtime: $(printf '%s\n' "$libraries" | grep -o "libclang_rt\.[a-z]*_osx_dynamic\.dylib" | sort -u | tr '\n' ' ')" >&2
            return 1 ;;
    esac
    echo "Runtime check: $(basename "$binary") links no sanitizer runtime"
}
