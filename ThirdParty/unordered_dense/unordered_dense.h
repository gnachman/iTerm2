///////////////////////// ankerl::unordered_dense::{map, set} /////////////////////////

// A fast & densely stored hashmap and hashset based on robin-hood backward shift deletion.
// Version 4.11.0
// https://github.com/martinus/unordered_dense
//
// Licensed under the MIT License <http://opensource.org/licenses/MIT>.
// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Martin Leitner-Ankerl <martin.ankerl@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#ifndef ANKERL_UNORDERED_DENSE_H
#define ANKERL_UNORDERED_DENSE_H

// see https://semver.org/spec/v2.0.0.html
#define ANKERL_UNORDERED_DENSE_VERSION_MAJOR 4  // NOLINT(cppcoreguidelines-macro-usage) incompatible API changes
#define ANKERL_UNORDERED_DENSE_VERSION_MINOR 11 // NOLINT(cppcoreguidelines-macro-usage) backwards compatible functionality
#define ANKERL_UNORDERED_DENSE_VERSION_PATCH 0  // NOLINT(cppcoreguidelines-macro-usage) backwards compatible bug fixes

// API versioning with inline namespace, see https://www.foonathan.net/2018/11/inline-namespaces/

// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#define ANKERL_UNORDERED_DENSE_VERSION_CONCAT1(major, minor, patch) v##major##_##minor##_##patch
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#define ANKERL_UNORDERED_DENSE_VERSION_CONCAT(major, minor, patch) ANKERL_UNORDERED_DENSE_VERSION_CONCAT1(major, minor, patch)
#define ANKERL_UNORDERED_DENSE_NAMESPACE   \
    ANKERL_UNORDERED_DENSE_VERSION_CONCAT( \
        ANKERL_UNORDERED_DENSE_VERSION_MAJOR, ANKERL_UNORDERED_DENSE_VERSION_MINOR, ANKERL_UNORDERED_DENSE_VERSION_PATCH)

#if defined(_MSVC_LANG)
#    define ANKERL_UNORDERED_DENSE_CPP_VERSION _MSVC_LANG
#else
#    define ANKERL_UNORDERED_DENSE_CPP_VERSION __cplusplus
#endif

#if defined(__GNUC__)
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#    define ANKERL_UNORDERED_DENSE_PACK(decl) decl __attribute__((__packed__))
#elif defined(_MSC_VER)
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#    define ANKERL_UNORDERED_DENSE_PACK(decl) __pragma(pack(push, 1)) decl __pragma(pack(pop))
#endif

// exceptions
#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
#    define ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS() 1 // NOLINT(cppcoreguidelines-macro-usage)
#else
#    define ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS() 0 // NOLINT(cppcoreguidelines-macro-usage)
#endif
#ifdef _MSC_VER
#    define ANKERL_UNORDERED_DENSE_NOINLINE __declspec(noinline)
#else
#    define ANKERL_UNORDERED_DENSE_NOINLINE __attribute__((noinline))
#endif

// data prefetch hint, a no-op when not supported
#if defined(__GNUC__) || defined(__clang__)
#    define ANKERL_UNORDERED_DENSE_PREFETCH(addr) __builtin_prefetch(addr) // NOLINT(cppcoreguidelines-macro-usage)
#else
#    define ANKERL_UNORDERED_DENSE_PREFETCH(addr) static_cast<void>(addr) // NOLINT(cppcoreguidelines-macro-usage)
#endif

// SSE2 is part of the x86-64 baseline, so the four-buckets-at-a-time probe is available on every
// x86-64 build without asking for it. Elsewhere, and in a build that defines this to 0, the scalar
// probe is used.
#if !defined(ANKERL_UNORDERED_DENSE_HAS_SSE2)
#    if defined(__SSE2__) || (defined(_MSC_VER) && (defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)))
#        define ANKERL_UNORDERED_DENSE_HAS_SSE2 1 // NOLINT(cppcoreguidelines-macro-usage)
#    else
#        define ANKERL_UNORDERED_DENSE_HAS_SSE2 0 // NOLINT(cppcoreguidelines-macro-usage)
#    endif
#endif

#if defined(__clang__) && defined(__has_attribute)
#    if __has_attribute(__no_sanitize__)
#        define ANKERL_UNORDERED_DENSE_DISABLE_UBSAN_UNSIGNED_INTEGER_CHECK \
            __attribute__((__no_sanitize__("unsigned-integer-overflow")))
#    endif
#endif

#if !defined(ANKERL_UNORDERED_DENSE_DISABLE_UBSAN_UNSIGNED_INTEGER_CHECK)
#    define ANKERL_UNORDERED_DENSE_DISABLE_UBSAN_UNSIGNED_INTEGER_CHECK
#endif

#if ANKERL_UNORDERED_DENSE_CPP_VERSION < 201703L
#    error ankerl::unordered_dense requires C++17 or higher
#else

#    if !defined(ANKERL_UNORDERED_DENSE_STD_MODULE)
// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#        define ANKERL_UNORDERED_DENSE_STD_MODULE 0
#    endif

#    if !ANKERL_UNORDERED_DENSE_STD_MODULE
#        include "stl.h"
#    endif
#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
#        include <emmintrin.h> // for _mm_loadu_si128, _mm_cmpeq_epi32, ...
#        if defined(_MSC_VER)
#            include <intrin.h> // for _BitScanForward
#        endif
#    endif

#    if __has_cpp_attribute(likely) && __has_cpp_attribute(unlikely) && ANKERL_UNORDERED_DENSE_CPP_VERSION >= 202002L
#        define ANKERL_UNORDERED_DENSE_LIKELY_ATTR [[likely]]     // NOLINT(cppcoreguidelines-macro-usage)
#        define ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR [[unlikely]] // NOLINT(cppcoreguidelines-macro-usage)
#        define ANKERL_UNORDERED_DENSE_LIKELY(x) (x)              // NOLINT(cppcoreguidelines-macro-usage)
#        define ANKERL_UNORDERED_DENSE_UNLIKELY(x) (x)            // NOLINT(cppcoreguidelines-macro-usage)
#    else
#        define ANKERL_UNORDERED_DENSE_LIKELY_ATTR   // NOLINT(cppcoreguidelines-macro-usage)
#        define ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR // NOLINT(cppcoreguidelines-macro-usage)

#        if defined(__GNUC__) || defined(__INTEL_COMPILER) || defined(__clang__)
#            define ANKERL_UNORDERED_DENSE_LIKELY(x) __builtin_expect(x, 1)   // NOLINT(cppcoreguidelines-macro-usage)
#            define ANKERL_UNORDERED_DENSE_UNLIKELY(x) __builtin_expect(x, 0) // NOLINT(cppcoreguidelines-macro-usage)
#        else
#            define ANKERL_UNORDERED_DENSE_LIKELY(x) (x)   // NOLINT(cppcoreguidelines-macro-usage)
#            define ANKERL_UNORDERED_DENSE_UNLIKELY(x) (x) // NOLINT(cppcoreguidelines-macro-usage)
#        endif

#    endif

namespace ankerl::unordered_dense {
inline namespace ANKERL_UNORDERED_DENSE_NAMESPACE {

namespace detail {

#    if ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS()

// make sure this is not inlined as it is slow and dramatically enlarges code, thus making other
// inlinings more difficult. Throws are also generally the slow path.
[[noreturn]] inline ANKERL_UNORDERED_DENSE_NOINLINE void on_error_key_not_found() {
    throw std::out_of_range("ankerl::unordered_dense::map::at(): key not found");
}
[[noreturn]] inline ANKERL_UNORDERED_DENSE_NOINLINE void on_error_bucket_overflow() {
    throw std::overflow_error("ankerl::unordered_dense: reached max bucket size, cannot increase size");
}
[[noreturn]] inline ANKERL_UNORDERED_DENSE_NOINLINE void on_error_too_many_elements() {
    throw std::out_of_range("ankerl::unordered_dense::map::replace(): too many elements");
}

#    else

[[noreturn]] inline void on_error_key_not_found() {
    abort();
}
[[noreturn]] inline void on_error_bucket_overflow() {
    abort();
}
[[noreturn]] inline void on_error_too_many_elements() {
    abort();
}

#    endif

#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
// Index of the lowest set bit, for the lane masks of the vector probe. x must not be zero.
[[nodiscard]] inline auto countr_zero(std::uint32_t x) -> unsigned {
#        if defined(_MSC_VER)
    unsigned long idx{};
    _BitScanForward(&idx, x);
    return static_cast<unsigned>(idx);
#        else
    return static_cast<unsigned>(__builtin_ctz(x));
#        endif
}
#    endif

} // namespace detail

// hash ///////////////////////////////////////////////////////////////////////

// This is a stripped-down implementation of wyhash: https://github.com/wangyi-fudan/wyhash
// No big-endian support (because different values on different machines don't matter),
// hardcodes seed and the secret, reformats the code, and clang-tidy fixes.
namespace detail::wyhash {

inline void mum(std::uint64_t* a, std::uint64_t* b) {
#    if defined(__SIZEOF_INT128__)
    __uint128_t r = *a;
    r *= *b;
    *a = static_cast<std::uint64_t>(r);
    *b = static_cast<std::uint64_t>(r >> 64U);
#    elif defined(_MSC_VER) && defined(_M_X64)
    *a = _umul128(*a, *b, b);
#    else
    std::uint64_t ha = *a >> 32U;
    std::uint64_t hb = *b >> 32U;
    std::uint64_t la = static_cast<std::uint32_t>(*a);
    std::uint64_t lb = static_cast<std::uint32_t>(*b);
    std::uint64_t hi{};
    std::uint64_t lo{};
    std::uint64_t rh = ha * hb;
    std::uint64_t rm0 = ha * lb;
    std::uint64_t rm1 = hb * la;
    std::uint64_t rl = la * lb;
    std::uint64_t t = rl + (rm0 << 32U);
    auto c = static_cast<std::uint64_t>(t < rl);
    lo = t + (rm1 << 32U);
    c += static_cast<std::uint64_t>(lo < t);
    hi = rh + (rm0 >> 32U) + (rm1 >> 32U) + c;
    *a = lo;
    *b = hi;
#    endif
}

// multiply and xor mix function, aka MUM
[[nodiscard]] inline auto mix(std::uint64_t a, std::uint64_t b) -> std::uint64_t {
    mum(&a, &b);
    return a ^ b;
}

// read functions. WARNING: we don't care about endianness, so results are different on big endian!
[[nodiscard]] inline auto r8(const std::uint8_t* p) -> std::uint64_t {
    std::uint64_t v{};
    std::memcpy(&v, p, 8U);
    return v;
}

[[nodiscard]] inline auto r4(const std::uint8_t* p) -> std::uint64_t {
    std::uint32_t v{};
    std::memcpy(&v, p, 4);
    return v;
}

// reads 1, 2, or 3 bytes
[[nodiscard]] inline auto r3(const std::uint8_t* p, std::size_t k) -> std::uint64_t {
    return (static_cast<std::uint64_t>(p[0]) << 16U) | (static_cast<std::uint64_t>(p[k >> 1U]) << 8U) | p[k - 1];
}

[[maybe_unused]] [[nodiscard]] inline auto hash(void const* key, std::size_t len) -> std::uint64_t {
    static constexpr auto secret = std::array{UINT64_C(0xa0761d6478bd642f),
                                              UINT64_C(0xe7037ed1a0b428db),
                                              UINT64_C(0x8ebc6af09c88c6e3),
                                              UINT64_C(0x589965cc75374cc3),
                                              UINT64_C(0x2d358dccaa6c78a5),
                                              UINT64_C(0x8bb84b93962eacc9),
                                              UINT64_C(0x4b33a62ed433d4a3)};

    auto const* p = static_cast<std::uint8_t const*>(key);
    std::uint64_t seed = secret[0];
    std::uint64_t a{};
    std::uint64_t b{};
    if (ANKERL_UNORDERED_DENSE_LIKELY(len <= 16))
        ANKERL_UNORDERED_DENSE_LIKELY_ATTR {
            if (ANKERL_UNORDERED_DENSE_LIKELY(len >= 8))
                ANKERL_UNORDERED_DENSE_LIKELY_ATTR {
                    // two (potentially overlapping) 8 byte reads cover the whole input
                    a = r8(p);
                    b = r8(p + len - 8);
                }
            else if (len >= 4) {
                a = r4(p);
                b = r4(p + len - 4);
            } else if (ANKERL_UNORDERED_DENSE_LIKELY(len > 0))
                ANKERL_UNORDERED_DENSE_LIKELY_ATTR {
                    // b stays zero: r3 packs all len bytes it is given into a, and there are at
                    // most three of them.
                    a = r3(p, len);
                }
            // ... and an empty input needs no branch of its own: it hashes whatever a and b were
            // declared with, which is the zero it has to be. Assigning it again here is what a
            // deletion sweep of this file kept pointing at.

            // Return, rather than falling through to the same expression at the end of the
            // function. Falling through makes seed, a and b values of two paths at once, and then
            // the compiler cannot fold the constant seed of this one into the mix: measured, the
            // short path costs 36 instructions that way and 24 this way.
            return mix(secret[1] ^ len, mix(a ^ secret[1], b ^ seed));
        }

    // Anything longer, in blocks of 16 bytes, ending on the same expression as above.
    std::size_t i = len;
    if (ANKERL_UNORDERED_DENSE_UNLIKELY(i > 48))
        ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
            std::uint64_t see1 = seed;
            std::uint64_t see2 = seed;
            // Six lanes cost three more accumulators to set up and fold back in, so the block
            // has to run more than once to pay for them. Entering it at 96 meant exactly one
            // iteration for everything from 97 to 192 bytes, which never can: measured, 23.4
            // cycles for a 100 byte key against 21.8 when it takes the 48 byte loop instead, and
            // 29.3 against 28.2 at 150. Above 192 the block runs at least twice and wins again --
            // 143.5 cycles against 147.1 at 1000 bytes -- so it keeps those.
            if (i > 192) {
                // 6 independent lanes: twice the instruction level parallelism of the 48 byte loop below
                std::uint64_t see3 = seed;
                std::uint64_t see4 = seed;
                std::uint64_t see5 = seed;
                do {
                    seed = mix(r8(p) ^ secret[1], r8(p + 8) ^ seed);
                    see1 = mix(r8(p + 16) ^ secret[2], r8(p + 24) ^ see1);
                    see2 = mix(r8(p + 32) ^ secret[3], r8(p + 40) ^ see2);
                    see3 = mix(r8(p + 48) ^ secret[4], r8(p + 56) ^ see3);
                    see4 = mix(r8(p + 64) ^ secret[5], r8(p + 72) ^ see4);
                    see5 = mix(r8(p + 80) ^ secret[6], r8(p + 88) ^ see5);
                    p += 96;
                    i -= 96;
                } while (ANKERL_UNORDERED_DENSE_LIKELY(i > 96));
                seed ^= see3 ^ see4 ^ see5;
            }
            while (i > 48) {
                seed = mix(r8(p) ^ secret[1], r8(p + 8) ^ seed);
                see1 = mix(r8(p + 16) ^ secret[2], r8(p + 24) ^ see1);
                see2 = mix(r8(p + 32) ^ secret[3], r8(p + 40) ^ see2);
                p += 48;
                i -= 48;
            }
            seed ^= see1 ^ see2;
            while (i > 16) {
                seed = mix(r8(p) ^ secret[1], r8(p + 8) ^ seed);
                i -= 16;
                p += 16;
            }

            // the tail lane only depends on the input, not on seed, so it can execute in parallel
            // with the lane loops above, and a single dependent mix finishes the hash
            auto tail = mix(r8(p + i - 16) ^ secret[2], r8(p + i - 8) ^ secret[3]);
            return mix(secret[1] ^ len, seed ^ tail);
        }
    while (ANKERL_UNORDERED_DENSE_UNLIKELY(i > 16))
        ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
            seed = mix(r8(p) ^ secret[1], r8(p + 8) ^ seed);
            i -= 16;
            p += 16;
        }
    a = r8(p + i - 16);
    b = r8(p + i - 8);

    return mix(secret[1] ^ len, mix(a ^ secret[1], b ^ seed));
}

[[nodiscard]] inline auto hash(std::uint64_t x) -> std::uint64_t {
    return detail::wyhash::mix(x, UINT64_C(0x9E3779B97F4A7C15));
}

} // namespace detail::wyhash

namespace detail {

struct nonesuch {};

template <class Default, class AlwaysVoid, template <class...> class Op, class... Args>
struct detector {
    using value_t = std::false_type;
    using type = Default;
};

template <class Default, template <class...> class Op, class... Args>
struct detector<Default, std::void_t<Op<Args...>>, Op, Args...> {
    using value_t = std::true_type;
    using type = Op<Args...>;
};

template <template <class...> class Op, class... Args>
using is_detected = typename detail::detector<detail::nonesuch, void, Op, Args...>::value_t;

template <template <class...> class Op, class... Args>
constexpr bool is_detected_v = is_detected<Op, Args...>::value;

template <typename>
constexpr bool dependent_false = false;

template <typename T>
using detect_avalanching = typename T::is_avalanching;

// The member written as a value instead of a type, which is the near miss that would otherwise
// answer "not avalanching" and say nothing about why.
template <typename T>
using detect_avalanching_as_value = decltype((void)T::is_avalanching);

template <typename T>
using detect_bool_value = std::enable_if_t<std::is_convertible_v<decltype(T::value), bool>>;

// What a hash's is_avalanching member means. void is this library's spelling, and Boost's original
// one; a type carrying a compile time bool is what Boost's documentation asks for now. Saying
// std::false_type there has to mean no rather than yes -- reading the member as a bare "it is
// there" would take a hash that declares itself ordinary and use it unmixed, which is the one
// answer that costs the table its distribution.
//
// Anything else is a mistake, and is said to be one rather than guessed at.
template <typename Hash>
[[nodiscard]] constexpr auto is_avalanching_member() -> bool {
    if constexpr (!is_detected_v<detect_avalanching, Hash>) {
        static_assert(!is_detected_v<detect_avalanching_as_value, Hash>,
                      "is_avalanching must be a type: write 'using is_avalanching = std::true_type;' "
                      "rather than 'static constexpr bool is_avalanching = true;'");
        return false;
    } else if constexpr (std::is_void_v<detect_avalanching<Hash>>) {
        return true;
    } else if constexpr (is_detected_v<detect_bool_value, detect_avalanching<Hash>>) {
        return static_cast<bool>(detect_avalanching<Hash>::value);
    } else {
        static_assert(dependent_false<Hash>,
                      "is_avalanching must be void, or a type with a compile time bool value such "
                      "as std::true_type or std::false_type");
        return false;
    }
}

} // namespace detail

// Whether a hash is high quality -- every bit of its result independently well distributed -- so
// that a table can index with those bits as they come instead of mixing them first. The default
// answer is the member typedef a hash can carry, `using is_avalanching = void;` or the equivalent
// `= std::true_type`. For a hash you cannot edit, specialize this instead; `std::false_type` is
// allowed too, and forces the mixing back on for a hash that promises more than it delivers.
//
// Deliberately the same name, the same two ways of answering and the same meaning as Boost's
// boost::hash_is_avalanching, so that a hash annotated for either library is read correctly by the
// other. See README 3.2.7.
template <typename Hash>
struct hash_is_avalanching : std::bool_constant<detail::is_avalanching_member<Hash>()> {};

template <typename Hash>
constexpr bool hash_is_avalanching_v = hash_is_avalanching<Hash>::value;

template <typename T, typename Enable = void>
struct hash {
    auto operator()(T const& obj) const noexcept(noexcept(std::declval<std::hash<T>>().operator()(std::declval<T const&>())))
        -> std::uint64_t {
        return std::hash<T>{}(obj);
    }
};

// Asked of hash_is_avalanching rather than of std::hash<T>::is_avalanching directly, so that there
// is one reader of the marker and not two: a std::hash spelling its marker the way Boost asks, or
// named avalanching by a specialization because it cannot be edited, reaches the table through here
// as well.
template <typename T>
struct hash<T, std::enable_if_t<hash_is_avalanching_v<std::hash<T>>>> {
    using is_avalanching = void;
    auto operator()(T const& obj) const noexcept(noexcept(std::declval<std::hash<T>>().operator()(std::declval<T const&>())))
        -> std::uint64_t {
        return std::hash<T>{}(obj);
    }
};

template <typename CharT>
struct hash<std::basic_string<CharT>> {
    using is_avalanching = void;
    auto operator()(std::basic_string<CharT> const& str) const noexcept -> std::uint64_t {
        return detail::wyhash::hash(str.data(), sizeof(CharT) * str.size());
    }
};

template <typename CharT>
struct hash<std::basic_string_view<CharT>> {
    using is_avalanching = void;
    auto operator()(std::basic_string_view<CharT> const& sv) const noexcept -> std::uint64_t {
        return detail::wyhash::hash(sv.data(), sizeof(CharT) * sv.size());
    }
};

template <class T>
struct hash<T*> {
    using is_avalanching = void;
    auto operator()(T* ptr) const noexcept -> std::uint64_t {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
        return detail::wyhash::hash(reinterpret_cast<std::uintptr_t>(ptr));
    }
};

template <class T>
struct hash<std::unique_ptr<T>> {
    using is_avalanching = void;
    auto operator()(std::unique_ptr<T> const& ptr) const noexcept -> std::uint64_t {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
        return detail::wyhash::hash(reinterpret_cast<std::uintptr_t>(ptr.get()));
    }
};

template <class T>
struct hash<std::shared_ptr<T>> {
    using is_avalanching = void;
    auto operator()(std::shared_ptr<T> const& ptr) const noexcept -> std::uint64_t {
        // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
        return detail::wyhash::hash(reinterpret_cast<std::uintptr_t>(ptr.get()));
    }
};

template <typename Enum>
struct hash<Enum, typename std::enable_if_t<std::is_enum_v<Enum>>> {
    using is_avalanching = void;
    auto operator()(Enum e) const noexcept -> std::uint64_t {
        using underlying = std::underlying_type_t<Enum>;
        return detail::wyhash::hash(static_cast<std::uint64_t>(static_cast<underlying>(e)));
    }
};

template <typename... Args>
struct tuple_hash_helper {
    // Converts the value into 64bit. If it is an integral type, just cast it. Mixing is doing the rest.
    // If it isn't an integral we need to hash it.
    template <typename Arg>
    [[nodiscard]] constexpr static auto to64(Arg const& arg) -> std::uint64_t {
        if constexpr (std::is_integral_v<Arg> || std::is_enum_v<Arg>) {
            return static_cast<std::uint64_t>(arg);
        } else {
            return hash<Arg>{}(arg);
        }
    }

    [[nodiscard]] ANKERL_UNORDERED_DENSE_DISABLE_UBSAN_UNSIGNED_INTEGER_CHECK static auto mix64(std::uint64_t state,
                                                                                                std::uint64_t v)
        -> std::uint64_t {
        return detail::wyhash::mix(state + v, std::uint64_t{0x9ddfea08eb382d69});
    }

    // Creates a buffer that holds all the data from each element of the tuple. If possible we memcpy the data directly. If
    // not, we hash the object and use this for the array. Size of the array is known at compile time, and memcpy is optimized
    // away, so filling the buffer is highly efficient. Finally, call wyhash with this buffer.
    template <typename T, std::size_t... Idx>
    [[nodiscard]] static auto calc_hash(T const& t, std::index_sequence<Idx...> /*unused*/) noexcept -> std::uint64_t {
        auto h = std::uint64_t{};
        ((h = mix64(h, to64(std::get<Idx>(t)))), ...);
        return h;
    }
};

template <typename... Args>
struct hash<std::tuple<Args...>> : tuple_hash_helper<Args...> {
    using is_avalanching = void;
    auto operator()(std::tuple<Args...> const& t) const noexcept -> std::uint64_t {
        return tuple_hash_helper<Args...>::calc_hash(t, std::index_sequence_for<Args...>{});
    }
};

template <typename A, typename B>
struct hash<std::pair<A, B>> : tuple_hash_helper<A, B> {
    using is_avalanching = void;
    auto operator()(std::pair<A, B> const& t) const noexcept -> std::uint64_t {
        return tuple_hash_helper<A, B>::calc_hash(t, std::index_sequence_for<A, B>{});
    }
};

// NOLINTNEXTLINE(cppcoreguidelines-macro-usage)
#    define ANKERL_UNORDERED_DENSE_HASH_STATICCAST(T)                         \
        template <>                                                           \
        struct hash<T> {                                                      \
            using is_avalanching = void;                                      \
            auto operator()(T const& obj) const noexcept -> std::uint64_t {   \
                return detail::wyhash::hash(static_cast<std::uint64_t>(obj)); \
            }                                                                 \
        }

#    if defined(__GNUC__) && !defined(__clang__)
#        pragma GCC diagnostic push
#        pragma GCC diagnostic ignored "-Wuseless-cast"
#    endif
// see https://en.cppreference.com/w/cpp/utility/hash
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(bool);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(char);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(signed char);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(unsigned char);
#    if ANKERL_UNORDERED_DENSE_CPP_VERSION >= 202002L && defined(__cpp_char8_t)
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(char8_t);
#    endif
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(char16_t);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(char32_t);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(wchar_t);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(short);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(unsigned short);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(int);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(unsigned int);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(long);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(long long);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(unsigned long);
ANKERL_UNORDERED_DENSE_HASH_STATICCAST(unsigned long long);

#    if defined(__GNUC__) && !defined(__clang__)
#        pragma GCC diagnostic pop
#    endif

// bucket_type //////////////////////////////////////////////////////////

namespace bucket_type {

struct standard {
    static constexpr std::uint32_t dist_inc = 1U << 8U;             // skip 1 byte fingerprint
    static constexpr std::uint32_t fingerprint_mask = dist_inc - 1; // mask for 1 byte of fingerprint

    std::uint32_t m_dist_and_fingerprint; // upper 3 byte: distance to original bucket. lower byte: fingerprint from hash
    std::uint32_t m_value_idx;            // index into the m_values vector.
};

ANKERL_UNORDERED_DENSE_PACK(struct big {
    static constexpr std::uint32_t dist_inc = 1U << 8U;             // skip 1 byte fingerprint
    static constexpr std::uint32_t fingerprint_mask = dist_inc - 1; // mask for 1 byte of fingerprint

    std::uint32_t m_dist_and_fingerprint; // upper 3 byte: distance to original bucket. lower byte: fingerprint from hash
    std::size_t m_value_idx;              // index into the m_values vector.
});

} // namespace bucket_type

namespace detail {

struct default_container_t {};

template <typename T>
using detect_is_transparent = typename T::is_transparent;

template <typename T>
using detect_iterator = typename T::iterator;

template <typename T>
using detect_reserve = decltype(std::declval<T&>().reserve(std::size_t{}));

// enable_if helpers

template <typename Mapped>
constexpr bool is_map_v = !std::is_void_v<Mapped>;

// clang-format off
template <typename Hash, typename KeyEqual>
constexpr bool is_transparent_v = is_detected_v<detect_is_transparent, Hash> && is_detected_v<detect_is_transparent, KeyEqual>;
// clang-format on

template <typename From, typename To1, typename To2>
constexpr bool is_neither_convertible_v = !std::is_convertible_v<From, To1> && !std::is_convertible_v<From, To2>;

template <typename T>
constexpr bool has_reserve = is_detected_v<detect_reserve, T>;

// base type for map has mapped_type
template <class T>
struct base_table_type_map {
    using mapped_type = T;
};

// base type for set doesn't have mapped_type
struct base_table_type_set {};

// A key's hash, finalized and ready for a table to index with, as produced by hash_for(). See the
// lookup section of table for what it is for; this is spelled table::precomputed_hash.
//
// Templated on the hasher and nothing else, because the hasher is all a hash depends on: a map, a
// set and a segmented_map that hash the key the same way can pass one around between them. It is a
// type of its own rather than a plain integer so that an integer does not convert to it by
// accident -- in particular what hash_function() returns, which is not this number.
template <typename Hash>
struct precomputed_hash {
    std::uint64_t m_mixed_hash;
};

} // namespace detail

// A hash that has to be a high quality one, for a codebase where they all are meant to be and
// forgetting to say so is the easy mistake:
//
//     template <class Key, class T>
//     using my_map = ankerl::unordered_dense::map<Key, T, require_avalanching<my_hash<Key>>>;
//
// Written into the alias rather than next to the hash so that the check is part of what the map
// is, and survives my_hash being reimplemented without its marker.
//
// It inherits, which is what keeps the hash's own operator() overloads and its is_transparent, and
// costs nothing: the wrapper is the same size as the hash and compiles to the same code.
template <typename Hash>
struct require_avalanching : Hash {
    static_assert(hash_is_avalanching_v<Hash>,
                  "hash is not avalanching: give it 'using is_avalanching = void;', or specialize "
                  "ankerl::unordered_dense::hash_is_avalanching for it, or stop requiring it here");
    static_assert(!std::is_final_v<Hash>,
                  "hash is final, so it cannot be wrapped: specialize "
                  "ankerl::unordered_dense::hash_is_avalanching for it instead");

    require_avalanching() = default;

    // So that a stateful hash can be handed over by value as well as braced into place -- an
    // aggregate would take require_avalanching<H>{h} but not require_avalanching<H>(h).
    explicit require_avalanching(Hash const& hash)
        : Hash(hash) {}

    // Restated rather than inherited, because a hash named avalanching by a specialization of
    // hash_is_avalanching has no member typedef to inherit.
    using is_avalanching = void;
};

// Very much like std::deque, but faster for indexing (in most cases). As of now this doesn't implement the full std::vector
// API, but merely what's necessary to work as an underlying container for ankerl::unordered_dense::{map, set}.
// It allocates blocks of equal size and puts them into the m_blocks vector. That means it can grow simply by adding a new
// block to the back of m_blocks, and doesn't double its size like an std::vector. The disadvantage is that memory is not
// linear and thus there is one more indirection necessary for indexing.
template <typename T, typename Allocator = std::allocator<T>, std::size_t MaxSegmentSizeBytes = 4096>
class segmented_vector {
    template <bool IsConst>
    class iter_t;

public:
    using allocator_type = Allocator;
    using pointer = typename std::allocator_traits<allocator_type>::pointer;
    using const_pointer = typename std::allocator_traits<allocator_type>::const_pointer;
    using difference_type = typename std::allocator_traits<allocator_type>::difference_type;
    using value_type = T;
    using size_type = std::size_t;
    using reference = T&;
    using const_reference = T const&;
    using iterator = iter_t<false>;
    using const_iterator = iter_t<true>;

private:
    using vec_alloc = typename std::allocator_traits<Allocator>::template rebind_alloc<pointer>;
    using vec_alloc_traits = std::allocator_traits<vec_alloc>;

    // The allocator lives in m_blocks, so these are what the assignment operators below act on --
    // and what their noexcept specifications are written over, so that the condition and the
    // promise cannot drift apart.
    static constexpr bool propagates_on_copy_assign = vec_alloc_traits::propagate_on_container_copy_assignment::value;
    static constexpr bool propagates_on_move_assign = vec_alloc_traits::propagate_on_container_move_assignment::value;
    static constexpr bool allocators_always_equal = vec_alloc_traits::is_always_equal::value;
    static constexpr bool propagates_on_swap = vec_alloc_traits::propagate_on_container_swap::value;

    std::vector<pointer, vec_alloc> m_blocks{};
    std::size_t m_size{};

    // Calculates the maximum number for x in  (s << x) <= max_val
    static constexpr auto num_bits_closest(std::size_t max_val, std::size_t s) -> std::size_t {
        auto f = std::size_t{0};
        while (s << (f + 1) <= max_val) {
            ++f;
        }
        return f;
    }

    using self_t = segmented_vector<T, Allocator, MaxSegmentSizeBytes>;
    static constexpr auto num_bits = num_bits_closest(MaxSegmentSizeBytes, sizeof(T));
    static constexpr auto num_elements_in_block = 1U << num_bits;
    static constexpr auto mask = num_elements_in_block - 1U;

    /**
     * Iterator class doubles as const_iterator and iterator
     */
    template <bool IsConst>
    class iter_t {
        using ptr_t = std::conditional_t<IsConst, segmented_vector::const_pointer const*, segmented_vector::pointer*>;
        ptr_t m_data{};
        std::size_t m_idx{};

        template <bool B>
        friend class iter_t;

    public:
        using difference_type = segmented_vector::difference_type;
        using value_type = segmented_vector::value_type;
        using reference = std::conditional_t<IsConst, value_type const&, value_type&>;
        using pointer = std::conditional_t<IsConst, segmented_vector::const_pointer, segmented_vector::pointer>;
        // Everything a random access iterator needs is right here -- the position is an index, so jumping and
        // subtracting are single operations. Saying "forward" instead meant std::distance walked the whole container
        // one element at a time to compute what operator-() answers directly, and every algorithm that requires
        // random access, std::sort over values() among them, was ill-formed over an iterator that can do the job.
        using iterator_category = std::random_access_iterator_tag;

        iter_t() noexcept = default;

        template <bool OtherIsConst, typename = std::enable_if_t<IsConst && !OtherIsConst>>
        // NOLINTNEXTLINE(google-explicit-constructor,hicpp-explicit-conversions)
        constexpr iter_t(iter_t<OtherIsConst> const& other) noexcept
            : m_data(other.m_data)
            , m_idx(other.m_idx) {}

        constexpr iter_t(ptr_t data, std::size_t idx) noexcept
            : m_data(data)
            , m_idx(idx) {}

        template <bool OtherIsConst, typename = std::enable_if_t<IsConst && !OtherIsConst>>
        constexpr auto operator=(iter_t<OtherIsConst> const& other) noexcept -> iter_t& {
            m_data = other.m_data;
            m_idx = other.m_idx;
            return *this;
        }

        constexpr auto operator++() noexcept -> iter_t& {
            ++m_idx;
            return *this;
        }

        constexpr auto operator++(int) noexcept -> iter_t {
            iter_t prev(*this);
            this->operator++();
            return prev;
        }

        constexpr auto operator--() noexcept -> iter_t& {
            --m_idx;
            return *this;
        }

        constexpr auto operator--(int) noexcept -> iter_t {
            iter_t prev(*this);
            this->operator--();
            return prev;
        }

        [[nodiscard]] constexpr auto operator+(difference_type diff) const noexcept -> iter_t {
            return {m_data, static_cast<std::size_t>(static_cast<difference_type>(m_idx) + diff)};
        }

        // n + it, which a random access iterator has to support just as it + n does
        [[nodiscard]] friend constexpr auto operator+(difference_type diff, iter_t const& it) noexcept -> iter_t {
            return it + diff;
        }

        // The cast is the one operator+() already does. Nothing instantiated these two before, because no algorithm
        // could reach them through a forward iterator, so the implicit signed-to-unsigned conversion sat here
        // unnoticed until clang's -Wsign-conversion saw std::sort use it.
        constexpr auto operator+=(difference_type diff) noexcept -> iter_t& {
            m_idx = static_cast<std::size_t>(static_cast<difference_type>(m_idx) + diff);
            return *this;
        }

        [[nodiscard]] constexpr auto operator-(difference_type diff) const noexcept -> iter_t {
            return {m_data, static_cast<std::size_t>(static_cast<difference_type>(m_idx) - diff)};
        }

        constexpr auto operator-=(difference_type diff) noexcept -> iter_t& {
            m_idx = static_cast<std::size_t>(static_cast<difference_type>(m_idx) - diff);
            return *this;
        }

        template <bool OtherIsConst>
        [[nodiscard]] constexpr auto operator-(iter_t<OtherIsConst> const& other) const noexcept -> difference_type {
            return static_cast<difference_type>(m_idx) - static_cast<difference_type>(other.m_idx);
        }

        constexpr auto operator*() const noexcept -> reference {
            return m_data[m_idx >> num_bits][m_idx & mask];
        }

        [[nodiscard]] constexpr auto operator[](difference_type diff) const noexcept -> reference {
            return *(*this + diff);
        }

        constexpr auto operator->() const noexcept -> pointer {
            return &m_data[m_idx >> num_bits][m_idx & mask];
        }

        template <bool O>
        [[nodiscard]] constexpr auto operator==(iter_t<O> const& o) const noexcept -> bool {
            return m_idx == o.m_idx;
        }

        template <bool O>
        [[nodiscard]] constexpr auto operator!=(iter_t<O> const& o) const noexcept -> bool {
            return !(*this == o);
        }

        template <bool O>
        [[nodiscard]] constexpr auto operator<(iter_t<O> const& o) const noexcept -> bool {
            return m_idx < o.m_idx;
        }

        template <bool O>
        [[nodiscard]] constexpr auto operator>(iter_t<O> const& o) const noexcept -> bool {
            return o < *this;
        }

        template <bool O>
        [[nodiscard]] constexpr auto operator<=(iter_t<O> const& o) const noexcept -> bool {
            return !(o < *this);
        }

        template <bool O>
        [[nodiscard]] constexpr auto operator>=(iter_t<O> const& o) const noexcept -> bool {
            return !(*this < o);
        }
    };

    // slow path: need to allocate a new segment every once in a while
    void increase_capacity() {
        auto ba = Allocator(m_blocks.get_allocator());

        // Room for the pointer first. push_back is the other thing here that can throw -- it
        // reallocates -- and it used to do so with the block already allocated and owned by
        // nobody, which leaked it. Reserving first means the only allocation still outstanding
        // when something fails is one that has not happened yet, and the push_back below cannot
        // fail because the capacity is already there. Grow geometrically to avoid reallocation
        // on every new segment.
        if (m_blocks.size() == m_blocks.capacity()) {
            m_blocks.reserve((std::max)(std::size_t{1}, m_blocks.capacity() * 2));
        }
        pointer block = std::allocator_traits<Allocator>::allocate(ba, num_elements_in_block);
        m_blocks.push_back(block);
    }

    // Moves everything from other
    void append_everything_from(segmented_vector&& other) { // NOLINT(cppcoreguidelines-rvalue-reference-param-not-moved)
        reserve(size() + other.size());
        for (auto&& o : other) {
            emplace_back(std::move(o));
        }
    }

    // Copies everything from other
    void append_everything_from(segmented_vector const& other) {
        reserve(size() + other.size());
        for (auto const& o : other) {
            emplace_back(o);
        }
    }

    void dealloc() {
        auto ba = Allocator(m_blocks.get_allocator());
        for (auto ptr : m_blocks) {
            std::allocator_traits<Allocator>::deallocate(ba, ptr, num_elements_in_block);
        }
    }

    [[nodiscard]] static constexpr auto calc_num_blocks_for_capacity(std::size_t capacity) {
        return (capacity + num_elements_in_block - 1U) / num_elements_in_block;
    }

    void resize_shrink(std::size_t new_size) {
        if constexpr (!std::is_trivially_destructible_v<T>) {
            for (std::size_t ix = new_size; ix < m_size; ++ix) {
                operator[](ix).~T();
            }
        }
        m_size = new_size;
    }

public:
    segmented_vector() = default;

    // NOLINTNEXTLINE(google-explicit-constructor,hicpp-explicit-conversions)
    segmented_vector(Allocator alloc)
        : m_blocks(vec_alloc(alloc)) {}

    // Uses alloc, unconditionally -- that is the whole point of an extended move constructor. It
    // used to delegate to move assignment, which cannot express it: assignment has to consult
    // propagate_on_container_move_assignment, so with a propagating allocator it adopted other's
    // and the allocator the caller named was quietly dropped.
    segmented_vector(segmented_vector&& other, Allocator alloc) noexcept(allocators_always_equal)
        : m_blocks(vec_alloc(alloc)) {
        if (allocators_always_equal || alloc == other.get_allocator()) {
            // Nothing to move element by element, the blocks just change hands.
            m_blocks = std::move(other.m_blocks);
            m_size = std::exchange(other.m_size, {});
        } else {
            append_everything_from(std::move(other));
        }
    }

    segmented_vector(segmented_vector const& other, Allocator alloc)
        : m_blocks(vec_alloc(alloc)) {
        append_everything_from(other);
    }

    segmented_vector(segmented_vector&& other) noexcept
        : segmented_vector(std::move(other), other.get_allocator()) {}

    segmented_vector(segmented_vector const& other)
        : m_blocks(vec_alloc_traits::select_on_container_copy_construction(other.m_blocks.get_allocator())) {
        append_everything_from(other);
    }

    auto operator=(segmented_vector const& other) -> segmented_vector& {
        if (this == &other) {
            return *this;
        }
        clear();
        if constexpr (propagates_on_copy_assign) {
            if (m_blocks.get_allocator() != other.m_blocks.get_allocator()) {
                // Everything still held has to go back through the old allocator before the new
                // one is adopted. Copy assignment and not move: which of the two propagates is
                // the inner vector's own pocca/pocma, and only pocca is known true here, so
                // assigning a temporary would consult pocma and silently keep the old allocator.
                dealloc();
                auto const empty_with_other_allocator = std::vector<pointer, vec_alloc>(other.m_blocks.get_allocator());
                m_blocks = empty_with_other_allocator;
            }
        }
        append_everything_from(other);
        return *this;
    }

    // Not unconditionally noexcept. When the allocator neither propagates nor compares equal --
    // std::pmr::polymorphic_allocator, for one -- the elements are moved one at a time into memory
    // this container allocates, so running out of it here has to be allowed to throw rather than
    // terminate. std::vector spells the condition the same way.
    auto operator=(segmented_vector&& other) noexcept(propagates_on_move_assign || allocators_always_equal)
        -> segmented_vector& {
        if (this == &other) {
            return *this;
        }
        clear();
        // Either the allocator comes along with the blocks or it is already the same one, and
        // either way the blocks can be taken over; std::vector's own move assignment does the
        // propagating in the first case.
        if (propagates_on_move_assign || m_blocks.get_allocator() == other.m_blocks.get_allocator()) {
            dealloc();
            m_blocks = std::move(other.m_blocks);
            m_size = std::exchange(other.m_size, {});
        } else {
            // Keeps its own allocator, because nothing said to take other's -- so the blocks it
            // already holds came from that same allocator and are reused rather than handed back
            // and immediately asked for again.
            append_everything_from(std::move(other));
        }
        return *this;
    }

    ~segmented_vector() {
        clear();
        dealloc();
    }

    [[nodiscard]] constexpr auto size() const -> std::size_t {
        return m_size;
    }

    [[nodiscard]] constexpr auto capacity() const -> std::size_t {
        return m_blocks.size() * num_elements_in_block;
    }

    // Indexing is highly performance critical
    [[nodiscard]] constexpr auto operator[](std::size_t i) const noexcept -> T const& {
        return m_blocks[i >> num_bits][i & mask];
    }

    [[nodiscard]] constexpr auto operator[](std::size_t i) noexcept -> T& {
        return m_blocks[i >> num_bits][i & mask];
    }

    [[nodiscard]] constexpr auto begin() -> iterator {
        return {m_blocks.data(), 0U};
    }
    [[nodiscard]] constexpr auto begin() const -> const_iterator {
        return {m_blocks.data(), 0U};
    }
    [[nodiscard]] constexpr auto cbegin() const -> const_iterator {
        return {m_blocks.data(), 0U};
    }

    [[nodiscard]] constexpr auto end() -> iterator {
        return {m_blocks.data(), m_size};
    }
    [[nodiscard]] constexpr auto end() const -> const_iterator {
        return {m_blocks.data(), m_size};
    }
    [[nodiscard]] constexpr auto cend() const -> const_iterator {
        return {m_blocks.data(), m_size};
    }

    [[nodiscard]] constexpr auto back() -> reference {
        return operator[](m_size - 1);
    }
    [[nodiscard]] constexpr auto back() const -> const_reference {
        return operator[](m_size - 1);
    }

    void pop_back() {
        back().~T();
        --m_size;
    }

    [[nodiscard]] auto empty() const {
        return 0 == m_size;
    }

    void reserve(std::size_t new_capacity) {
        m_blocks.reserve(calc_num_blocks_for_capacity(new_capacity));
        while (new_capacity > capacity()) {
            increase_capacity();
        }
    }

    void resize(std::size_t const count) {
        if (count < m_size) {
            resize_shrink(count);
        } else if (count > m_size) {
            std::size_t const new_elems = count - m_size;
            reserve(count);
            for (std::size_t ix = 0; ix < new_elems; ++ix) {
                emplace_back();
            }
        }
    }

    void resize(std::size_t const count, value_type const& value) {
        if (count < m_size) {
            resize_shrink(count);
        } else if (count > m_size) {
            std::size_t const new_elems = count - m_size;
            reserve(count);
            for (std::size_t ix = 0; ix < new_elems; ++ix) {
                emplace_back(value);
            }
        }
    }

    [[nodiscard]] auto get_allocator() const -> allocator_type {
        return allocator_type{m_blocks.get_allocator()};
    }

    // Exchanging two pointers and a size, and the inner vector's own swap exchanges the allocators
    // exactly when propagate_on_container_swap says to -- so this answers the allocator question
    // the way std::vector does, and a map gets the same answer whichever container backs it.
    // Without a member swap, std::swap fell back to a move construction and two move assignments:
    // O(n) for an operation that needs none, able to throw from inside a noexcept swap, and a
    // different answer from the flat container for the same map.
    void swap(segmented_vector& other) noexcept(propagates_on_swap || allocators_always_equal) {
        using std::swap;
        swap(m_blocks, other.m_blocks);
        swap(m_size, other.m_size);
    }

    friend void swap(segmented_vector& a, segmented_vector& b) noexcept(noexcept(a.swap(b))) {
        a.swap(b);
    }

    template <class... Args>
    auto emplace_back(Args&&... args) -> reference {
        if (m_size == capacity()) {
            increase_capacity();
        }
        auto* ptr = static_cast<void*>(&operator[](m_size));
        auto& ref = *new (ptr) T(std::forward<Args>(args)...);
        ++m_size;
        return ref;
    }

    void clear() {
        if constexpr (!std::is_trivially_destructible_v<T>) {
            for (std::size_t i = 0, s = size(); i < s; ++i) {
                operator[](i).~T();
            }
        }
        m_size = 0;
    }

    void shrink_to_fit() {
        auto ba = Allocator(m_blocks.get_allocator());
        auto num_blocks_required = calc_num_blocks_for_capacity(m_size);
        while (m_blocks.size() > num_blocks_required) {
            std::allocator_traits<Allocator>::deallocate(ba, m_blocks.back(), num_elements_in_block);
            m_blocks.pop_back();
        }
        m_blocks.shrink_to_fit();
    }
};

namespace detail {

// This is it, the table. Doubles as map and set, and uses `void` for T when its used as a set.
template <class Key,
          class T, // when void, treat it as a set.
          class Hash,
          class KeyEqual,
          class AllocatorOrContainer,
          class Bucket,
          class BucketContainer,
          bool IsSegmented>
class table : public std::conditional_t<is_map_v<T>, base_table_type_map<T>, base_table_type_set> {
    using underlying_value_type = std::conditional_t<is_map_v<T>, std::pair<Key, T>, Key>;
    using underlying_container_type = std::conditional_t<IsSegmented,
                                                         segmented_vector<underlying_value_type, AllocatorOrContainer>,
                                                         std::vector<underlying_value_type, AllocatorOrContainer>>;

public:
    using value_container_type = std::
        conditional_t<is_detected_v<detect_iterator, AllocatorOrContainer>, AllocatorOrContainer, underlying_container_type>;

private:
    using bucket_alloc =
        typename std::allocator_traits<typename value_container_type::allocator_type>::template rebind_alloc<Bucket>;
    using default_bucket_container_type =
        std::conditional_t<IsSegmented, segmented_vector<Bucket, bucket_alloc>, std::vector<Bucket, bucket_alloc>>;

    using bucket_container_type = std::conditional_t<std::is_same_v<BucketContainer, detail::default_container_t>,
                                                     default_bucket_container_type,
                                                     BucketContainer>;

    static constexpr std::uint8_t initial_shifts = 64 - 2; // 2^(64-m_shift) number of buckets
    static constexpr float default_max_load_factor = 0.8F;

    // The default bucket container is a std::vector: one allocation, reached through data().
    static constexpr bool has_contiguous_buckets =
        !IsSegmented && std::is_same_v<BucketContainer, detail::default_container_t>;

    // The probe can read four buckets at once where the bucket array is contiguous and the bucket
    // is the standard 8 byte one, on a platform with SSE2.
    static constexpr bool has_simd_scan = ANKERL_UNORDERED_DENSE_HAS_SSE2 && has_contiguous_buckets &&
                                          std::is_same_v<Bucket, ankerl::unordered_dense::bucket_type::standard>;

    // Four buckets read from any bucket index reach up to three past the end of the array, so the
    // array carries that many extra, written by allocate_buckets_from_shift() and copied along
    // with the rest. They hold a dist_and_fingerprint no key can expect and no bucket can hold
    // less than, and a value index no value has, so a scan passes over them as it would over
    // occupied buckets that are not the answer -- and the wrap to bucket zero is taken only where a
    // scan moves on, which is rare. bucket_count() does not count them.
    static constexpr std::size_t bucket_padding = has_simd_scan ? 3 : 0;

    // Named, and covering both containers, so that the promise and the recovery that exists for
    // when the promise cannot be made are spelled the same way and cannot drift apart -- the same
    // reason segmented_vector names its propagation traits. Covering only m_values would be wrong
    // twice over: it would leave m_buckets free to throw out of a noexcept function, and it would
    // compile a rethrow into one, which gcc rejects outright.
    static constexpr bool move_assign_is_nothrow =
        std::is_nothrow_move_assignable_v<value_container_type> && std::is_nothrow_move_assignable_v<bucket_container_type> &&
        std::is_nothrow_move_assignable_v<Hash> && std::is_nothrow_move_assignable_v<KeyEqual>;

public:
    using key_type = Key;
    using value_type = typename value_container_type::value_type;
    using size_type = typename value_container_type::size_type;
    using difference_type = typename value_container_type::difference_type;
    using hasher = Hash;
    using key_equal = KeyEqual;
    using allocator_type = typename value_container_type::allocator_type;
    using reference = typename value_container_type::reference;
    using const_reference = typename value_container_type::const_reference;
    using pointer = typename value_container_type::pointer;
    using const_pointer = typename value_container_type::const_pointer;
    using const_iterator = typename value_container_type::const_iterator;
    using iterator = std::conditional_t<is_map_v<T>, typename value_container_type::iterator, const_iterator>;
    using bucket_type = Bucket;

    // What hash_for() returns; see the lookup section below. Shared by every table with this
    // hasher, whatever else it is made of, because that is exactly the set of tables the hash is
    // good for.
    using precomputed_hash = detail::precomputed_hash<Hash>;

private:
    using value_idx_type = decltype(Bucket::m_value_idx);
    using dist_and_fingerprint_type = decltype(Bucket::m_dist_and_fingerprint);

    // what the padding buckets hold, see bucket_padding
    static constexpr auto sentinel_dist_and_fingerprint = static_cast<dist_and_fingerprint_type>(0x7FFFFFFFU);
    static constexpr auto sentinel_value_idx = (std::numeric_limits<value_idx_type>::max)();

    static_assert(std::is_trivially_destructible_v<Bucket>, "assert there's no need to call destructor / std::destroy");
    static_assert(std::is_trivially_copyable_v<Bucket>, "assert we can just memset / memcpy");

    // m_dist_and_fingerprint packs two fields into one integer, and these are what keeps them from
    // reaching into each other. A bucket type is something a user can supply, so this is checked
    // here rather than assumed.
    //
    // The fingerprint has to stay strictly below dist_inc. A mask that overlaps it lets hash bits
    // add to the distance a bucket claims, which silently reorders the robin hood sequence that
    // every probe depends on -- and a mask that reaches the bit above turns a fresh bucket into one
    // that reads as further from home than it is. Fewer fingerprint bits than dist_inc allows is
    // merely a weaker fingerprint, so the bound is one-sided.
    static_assert(Bucket::fingerprint_mask < Bucket::dist_inc,
                  "the fingerprint must fit strictly below dist_inc, or it changes the distance");
    // And dist_inc has to be a single bit, because the distance is incremented by adding it: two
    // bits set would carry into the fingerprint on the very first step away from home.
    static_assert(0 != Bucket::dist_inc && 0 == (Bucket::dist_inc & (Bucket::dist_inc - 1)),
                  "dist_inc must be a power of two, so that adding it only touches the distance");

    value_container_type m_values{}; // Contains all the key-value pairs in one densely stored container. No holes.
    bucket_container_type m_buckets{};
    std::size_t m_max_bucket_capacity = 0;
    value_idx_type m_bucket_mask = 0; // bucket_count() - 1; works because bucket_count() is always a power of two
    float m_max_load_factor = default_max_load_factor;
    Hash m_hash{};
    KeyEqual m_equal{};
    std::uint8_t m_shifts = initial_shifts;

    [[nodiscard]] auto next(value_idx_type bucket_idx) const -> value_idx_type {
        return static_cast<value_idx_type>((bucket_idx + 1U) & m_bucket_mask);
    }

    // Helper to access bucket through pointer types
    [[nodiscard]] static constexpr auto at(bucket_container_type& bucket, std::size_t offset) -> Bucket& {
        return bucket[offset];
    }

    [[nodiscard]] static constexpr auto at(const bucket_container_type& bucket, std::size_t offset) -> const Bucket& {
        return bucket[offset];
    }

    // use the dist_inc and dist_dec functions so that std::uint16_t types work without warning
    [[nodiscard]] static constexpr auto dist_inc(dist_and_fingerprint_type x) -> dist_and_fingerprint_type {
        return static_cast<dist_and_fingerprint_type>(x + Bucket::dist_inc);
    }

    [[nodiscard]] static constexpr auto dist_dec(dist_and_fingerprint_type x) -> dist_and_fingerprint_type {
        return static_cast<dist_and_fingerprint_type>(x - Bucket::dist_inc);
    }

    // The goal of mixed_hash is to always produce a high quality 64bit hash.
    template <typename K>
    [[nodiscard]] constexpr auto mixed_hash(K const& key) const -> std::uint64_t {
        if constexpr (hash_is_avalanching_v<Hash>) {
            // we know that the hash is good because is_avalanching.
            if constexpr (sizeof(decltype(m_hash(key))) < sizeof(std::uint64_t)) {
                // 32bit hash and is_avalanching => multiply with a constant to avalanche bits upwards
                return m_hash(key) * UINT64_C(0x9ddfea08eb382d69);
            } else {
                // 64bit and is_avalanching => only use the hash itself.
                return m_hash(key);
            }
        } else {
            // not is_avalanching => apply wyhash
            return wyhash::hash(m_hash(key));
        }
    }

    [[nodiscard]] constexpr auto dist_and_fingerprint_from_hash(std::uint64_t hash) const -> dist_and_fingerprint_type {
        return Bucket::dist_inc | (static_cast<dist_and_fingerprint_type>(hash) & Bucket::fingerprint_mask);
    }

    [[nodiscard]] constexpr auto bucket_idx_from_hash(std::uint64_t hash) const -> value_idx_type {
        return static_cast<value_idx_type>(hash >> m_shifts);
    }

    [[nodiscard]] static constexpr auto get_key(value_type const& vt) -> key_type const& {
        if constexpr (is_map_v<T>) {
            return vt.first;
        } else {
            return vt;
        }
    }

    template <typename K>
    [[nodiscard]] auto next_while_less(K const& key) const -> Bucket {
        auto hash = mixed_hash(key);
        auto dist_and_fingerprint = dist_and_fingerprint_from_hash(hash);
        auto bucket_idx = bucket_idx_from_hash(hash);

        while (dist_and_fingerprint < at(m_buckets, bucket_idx).m_dist_and_fingerprint) {
            dist_and_fingerprint = dist_inc(dist_and_fingerprint);
            bucket_idx = next(bucket_idx);
        }
        return {dist_and_fingerprint, bucket_idx};
    }

    void place_and_shift_up(Bucket bucket, value_idx_type place) {
        // cache mask in a local so the bucket stores can't alias it
        auto const mask = m_bucket_mask;
#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
        // NOLINTBEGIN(portability-simd-intrinsics) -- this is the x86 path, on purpose
        if constexpr (has_simd_scan) {
            // Four buckets at once, the way the probe reads them.
            //
            // Whether a bucket is occupied is a coin flip -- measured over 8 million inserts into a
            // table at its load factor, 73% shift nothing, 11% shift one, and the rest tail off --
            // and the loop below asks it once per bucket, so it paid 0.61 mispredictions per
            // insert. Here the four answers arrive as one mask: the contents are built as if every
            // bucket moved one along, and a blend keeps that for the run of occupied buckets plus
            // the empty one it ends in, and the old contents beyond. No decision per bucket; the
            // one branch left is "did the run end inside these four", which it does 91% of the
            // time. The loop takes the rest, and the last three buckets before the sentinels, so
            // that the four wide store never touches a sentinel. That bound is hygiene rather than
            // correctness, and a mutation sweep says so: with it wrong in every way, a sentinel in
            // the window reads as occupied and is written back as it was, and the three of them
            // are exactly enough padding for the window. Measured: 0.24 mispredictions and 46
            // cycles per insert where the loop alone cost 52, and build64 10% faster.
            if (ANKERL_UNORDERED_DENSE_LIKELY(std::size_t{place} + 3 <= mask)) {
                auto* gp = m_buckets.data() + place;
                auto lo = _mm_loadu_si128(reinterpret_cast<__m128i const*>(gp));     // NOLINT
                auto hi = _mm_loadu_si128(reinterpret_cast<__m128i const*>(gp + 2)); // NOLINT
                auto const dists =
                    _mm_castps_si128(_mm_shuffle_ps(_mm_castsi128_ps(lo), _mm_castsi128_ps(hi), _MM_SHUFFLE(2, 0, 2, 0)));
                auto const empty =
                    static_cast<unsigned>(_mm_movemask_ps(_mm_castsi128_ps(_mm_cmpeq_epi32(dists, _mm_setzero_si128()))));
                if (ANKERL_UNORDERED_DENSE_LIKELY(empty != 0)) {
                    // how many occupied buckets come before the first empty one: 0 to 3
                    auto const run = detail::countr_zero(empty);
                    auto const inc = static_cast<int>(Bucket::dist_inc);
                    static_assert(sizeof(Bucket) == 8);
                    auto const fresh = _mm_loadl_epi64(reinterpret_cast<__m128i const*>(&bucket)); // NOLINT
                    // [bucket, b0] and [b1, b2], each moved bucket one distance further from home
                    auto const moved_lo =
                        _mm_add_epi32(_mm_or_si128(_mm_slli_si128(lo, 8), fresh), _mm_setr_epi32(0, 0, inc, 0));
                    auto const moved_hi = _mm_add_epi32(_mm_or_si128(_mm_slli_si128(hi, 8), _mm_srli_si128(lo, 8)),
                                                        _mm_setr_epi32(inc, 0, inc, 0));
                    // buckets 0..run take the moved contents, the rest keep theirs
                    // rows are 32 bytes, so with the table aligned both halves of every row are
                    alignas(16) static constexpr std::array<std::array<std::int32_t, 8>, 4> keep = {
                        { {{-1, -1, 0, 0, 0, 0, 0, 0}},
                          {{-1, -1, -1, -1, 0, 0, 0, 0}},
                          {{-1, -1, -1, -1, -1, -1, 0, 0}},
                          {{-1, -1, -1, -1, -1, -1, -1, -1}},
                        }};
                    auto const keep_lo = _mm_load_si128(reinterpret_cast<__m128i const*>(keep[run].data()));     // NOLINT
                    auto const keep_hi = _mm_load_si128(reinterpret_cast<__m128i const*>(keep[run].data() + 4)); // NOLINT
                    lo = _mm_or_si128(_mm_and_si128(keep_lo, moved_lo), _mm_andnot_si128(keep_lo, lo));
                    hi = _mm_or_si128(_mm_and_si128(keep_hi, moved_hi), _mm_andnot_si128(keep_hi, hi));
                    _mm_storeu_si128(reinterpret_cast<__m128i*>(gp), lo);     // NOLINT
                    _mm_storeu_si128(reinterpret_cast<__m128i*>(gp + 2), hi); // NOLINT
                    return;
                }
            }
        }
        // NOLINTEND(portability-simd-intrinsics)
#    endif
        while (0 != at(m_buckets, place).m_dist_and_fingerprint) {
            bucket = std::exchange(at(m_buckets, place), bucket);
            bucket.m_dist_and_fingerprint = dist_inc(bucket.m_dist_and_fingerprint);
            place = static_cast<value_idx_type>((place + 1U) & mask);
        }
        at(m_buckets, place) = bucket;
    }

    void erase_and_shift_down(value_idx_type bucket_idx) {
        // cache mask in a local so the bucket stores can't alias it
        auto const mask = m_bucket_mask;
#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
        // NOLINTBEGIN(portability-simd-intrinsics) -- this is the x86 path, on purpose
        if constexpr (has_simd_scan) {
            // The mirror of place_and_shift_up: the four buckets after the one being erased, read
            // at once. A bucket moves back one if it is displaced, that is at distance two or
            // more; the run of displaced buckets after the victim all move back by one, and the
            // slot where the run ends becomes the empty one. Measured, the run is empty 73% of
            // the time and one long 11%, so asking per bucket was a coin flip per erase.
            //
            // The bound keeps the four wide store off the sentinels. As with the insert, a
            // mutation sweep found it is hygiene and not correctness: a sentinel inside the
            // window reads as displaced, which only ever sends the erase to the loop below.
            if (ANKERL_UNORDERED_DENSE_LIKELY(std::size_t{bucket_idx} + 4 <= mask)) {
                auto* gp = m_buckets.data() + bucket_idx;
                auto const rlo = _mm_loadu_si128(reinterpret_cast<__m128i const*>(gp + 1)); // NOLINT  [b1, b2]
                auto const rhi = _mm_loadu_si128(reinterpret_cast<__m128i const*>(gp + 3)); // NOLINT  [b3, b4]
                auto const dists =
                    _mm_castps_si128(_mm_shuffle_ps(_mm_castsi128_ps(rlo), _mm_castsi128_ps(rhi), _MM_SHUFFLE(2, 0, 2, 0)));
                // at home or empty: distance below two, which is the value below 2 * dist_inc
                static_assert(Bucket::dist_inc == (1U << 8U));
                auto const settled = static_cast<unsigned>(
                    _mm_movemask_ps(_mm_castsi128_ps(_mm_cmpeq_epi32(_mm_srli_epi32(dists, 9), _mm_setzero_si128()))));
                if (ANKERL_UNORDERED_DENSE_LIKELY(settled != 0)) {
                    auto const run = detail::countr_zero(settled); // displaced buckets after the victim, 0..3
                    auto const inc = static_cast<int>(Bucket::dist_inc);
                    // every bucket one closer to home, in the victim's window
                    auto const moved_lo = _mm_sub_epi32(rlo, _mm_setr_epi32(inc, 0, inc, 0));
                    auto const moved_hi = _mm_sub_epi32(rhi, _mm_setr_epi32(inc, 0, inc, 0));
                    // what the window holds now, for the buckets past the run: [victim, b1] and [b2, b3]
                    auto const old_lo = _mm_slli_si128(rlo, 8);
                    auto const old_hi = _mm_or_si128(_mm_slli_si128(rhi, 8), _mm_srli_si128(rlo, 8));
                    // buckets below run move, the one at run empties, the ones above stay
                    alignas(16) static constexpr std::array<std::array<std::int32_t, 8>, 5> below = {
                        { {{0, 0, 0, 0, 0, 0, 0, 0}},
                          {{-1, -1, 0, 0, 0, 0, 0, 0}},
                          {{-1, -1, -1, -1, 0, 0, 0, 0}},
                          {{-1, -1, -1, -1, -1, -1, 0, 0}},
                          {{-1, -1, -1, -1, -1, -1, -1, -1}},
                        }};
                    auto const take_lo = _mm_load_si128(reinterpret_cast<__m128i const*>(below[run].data()));         // NOLINT
                    auto const take_hi = _mm_load_si128(reinterpret_cast<__m128i const*>(below[run].data() + 4));     // NOLINT
                    auto const gone_lo = _mm_load_si128(reinterpret_cast<__m128i const*>(below[run + 1].data()));     // NOLINT
                    auto const gone_hi = _mm_load_si128(reinterpret_cast<__m128i const*>(below[run + 1].data() + 4)); // NOLINT
                    auto const lo = _mm_or_si128(_mm_and_si128(take_lo, moved_lo), _mm_andnot_si128(gone_lo, old_lo));
                    auto const hi = _mm_or_si128(_mm_and_si128(take_hi, moved_hi), _mm_andnot_si128(gone_hi, old_hi));
                    _mm_storeu_si128(reinterpret_cast<__m128i*>(gp), lo);     // NOLINT
                    _mm_storeu_si128(reinterpret_cast<__m128i*>(gp + 2), hi); // NOLINT
                    return;
                }
            }
        }
        // NOLINTEND(portability-simd-intrinsics)
#    endif

        // shift down until either empty or an element with correct spot is found
        auto next_bucket_idx = static_cast<value_idx_type>((bucket_idx + 1U) & mask);
        while (at(m_buckets, next_bucket_idx).m_dist_and_fingerprint >= Bucket::dist_inc * 2) {
            auto& next_bucket = at(m_buckets, next_bucket_idx);
            at(m_buckets, bucket_idx) = {dist_dec(next_bucket.m_dist_and_fingerprint), next_bucket.m_value_idx};
            bucket_idx = std::exchange(next_bucket_idx, static_cast<value_idx_type>((next_bucket_idx + 1U) & mask));
        }
        at(m_buckets, bucket_idx) = {};
    }

    [[nodiscard]] static constexpr auto calc_num_buckets(std::uint8_t shifts) -> std::size_t {
        return (std::min)(max_bucket_count(), std::size_t{1} << (64U - shifts));
    }

    [[nodiscard]] constexpr auto calc_shifts_for_size(std::size_t s) const -> std::uint8_t {
        auto shifts = initial_shifts;
        // Stopping once the array is as large as it may get is what keeps this from running off the
        // end. calc_num_buckets() saturates at max_bucket_count(), so past that point the capacity
        // being compared stops growing while the loop keeps decrementing -- and for any size above
        // max_bucket_count() * max_load_factor() it used to walk all the way to zero. A shift of
        // zero then asks calc_num_buckets() for `1 << 64`, which is undefined and in practice one:
        // a table sized for billions of elements would come back with a single bucket and a mask of
        // zero, and the next probe reads past the end of it. Reachable from rehash(), which does not
        // allocate the values and so has nothing to fail first.
        while (shifts > 0 && calc_num_buckets(shifts) < max_bucket_count() &&
               static_cast<std::size_t>(static_cast<float>(calc_num_buckets(shifts)) * max_load_factor()) < s) {
            --shifts;
        }
        return shifts;
    }

    // assumes m_values has data, m_buckets=m_buckets_end=nullptr, m_shifts is INITIAL_SHIFTS
    void copy_buckets(table const& other) {
        // assumes m_values has already the correct data copied over.
        if (empty()) {
            // Nothing to index, so stay in the state a default constructed table is in and let the
            // first insert allocate. Copying an empty table therefore allocates nothing either.
            m_shifts = initial_shifts;
        } else {
            if constexpr (!has_contiguous_buckets) {
                allocate_buckets_from_shift(other.m_shifts);
                for (auto i = 0UL; i < bucket_count(); ++i) {
                    at(m_buckets, i) = at(other.m_buckets, i);
                }
            } else {
                // One pass, not two. This used to grow the array with resize(), which value
                // initialises every bucket it adds, and then memcpy over all of it -- so every byte
                // of the bucket array was written twice, and for a large map the wasted half is a
                // memset of megabytes. assign() copies straight into the new storage.
                //
                // assign() and not m_buckets = other.m_buckets, which would consult pocca: the
                // allocator question is answered by the caller, and this is also reached from the
                // move assignment's differing-allocator branch, where adopting other's would be
                // exactly wrong.
                m_buckets.assign(other.m_buckets.begin(), other.m_buckets.end());
                m_shifts = other.m_shifts;
                describe_buckets(other.bucket_count());
            }
        }
    }

    // The part of copy assignment that can throw, kept separate so the operator can put the table
    // back together if it does.
    void copy_everything_from(table const& other) {
        // The assignment below takes other's allocator (pocca), and the buckets have to follow it,
        // or the container's two halves end up on different allocators and get_allocator() -- which
        // reports m_values' -- stops describing the bucket array, which the "same allocator" check
        // in the move assignment relies on it doing.
        //
        // Done before the copy rather than after: it is the same allocator either way, both
        // containers are empty here so it cannot throw, and doing it first means a copy that fails
        // part way through cannot leave the two halves disagreeing. Copy assignment and not move:
        // move would consult pocma, a different question, and not the one answered true here.
        if constexpr (std::allocator_traits<allocator_type>::propagate_on_container_copy_assignment::value) {
            // Rebound explicitly: m_values' allocator and m_buckets' are different types, and
            // comparing them directly is ambiguous rather than merely unusual.
            auto const wanted = typename bucket_container_type::allocator_type(other.m_values.get_allocator());
            if (m_buckets.get_allocator() != wanted) {
                auto const empty_with_other_allocator = bucket_container_type(wanted);
                m_buckets = empty_with_other_allocator;
            }
        }

        m_values = other.m_values;
        m_max_load_factor = other.m_max_load_factor;
        m_hash = other.m_hash;
        m_equal = other.m_equal;
        copy_buckets(other); // sets m_shifts on both of its branches
    }

    // The half of move assignment that can throw, so the caller can put the table back together if
    // it does. Its twin for copies is above.
    // NOLINTNEXTLINE(cppcoreguidelines-rvalue-reference-param-not-moved) -- moved from member by member
    void move_everything_from(table&& other) {
        m_values = std::move(other.m_values);
        other.m_values.clear();

        // we can only reuse m_buckets when both maps have the same allocator!
        if (get_allocator() == other.get_allocator()) {
            m_buckets = std::move(other.m_buckets);
            other.m_buckets.clear();
            m_max_bucket_capacity = std::exchange(other.m_max_bucket_capacity, 0);
            m_bucket_mask = std::exchange(other.m_bucket_mask, 0);
            m_shifts = std::exchange(other.m_shifts, initial_shifts);
            m_max_load_factor = std::exchange(other.m_max_load_factor, default_max_load_factor);
            m_hash = std::exchange(other.m_hash, {});
            m_equal = std::exchange(other.m_equal, {});
            // The exchanges above leave "other" exactly as a default constructed table looks, so it
            // is already usable and does not need buckets handed back to it. It used to get a
            // freshly allocated set here, which is an allocation -- and a way to throw -- inside an
            // operation that is otherwise noexcept and needs neither.
        } else {
            // set max_load_factor *before* copying the other's buckets, so we have the same behavior
            m_max_load_factor = other.m_max_load_factor;

            // copy_buckets sets m_buckets, m_num_buckets, m_max_bucket_capacity, m_shifts
            copy_buckets(other);
            // clear's the other's buckets so other is now already usable.
            other.clear_buckets();
            m_hash = other.m_hash;
            m_equal = other.m_equal;
        }
        // map "other" is now already usable, it's empty.
    }

    // Back to what a default constructed table holds. An assignment gives the buckets back before
    // it knows whether it can build new ones, and in between the table holds values it has no way
    // to find -- size() elements and no bucket array at all, which no operation is prepared for. If
    // an exception leaves that window this is where it lands: assignment owes the basic guarantee,
    // which means valid and not merely non-leaking, and with no buckets the only valid state is
    // empty. Every step is noexcept, so the recovery cannot fail on its way out.
    // Deliberately not deallocate_buckets(), which is otherwise the same three stores: that one
    // also calls shrink_to_fit(), which is allowed to allocate and is not noexcept, and this runs
    // while an exception is already in flight.
    void reset_to_empty() noexcept {
        m_values.clear();
        m_buckets.clear();
        m_max_bucket_capacity = 0;
        m_bucket_mask = 0;
        m_shifts = initial_shifts;
    }

    /**
     * True when no element can be added any more without increasing the size
     */
    [[nodiscard]] auto is_full() const -> bool {
        return size() > m_max_bucket_capacity;
    }

    void deallocate_buckets() {
        m_buckets.clear();
        m_buckets.shrink_to_fit();
        m_max_bucket_capacity = 0;
        m_bucket_mask = 0;
    }

    // Takes the shift rather than reading m_shifts, so that nothing describing the bucket array is
    // written until an array of that size exists. Callers used to assign m_shifts and then
    // allocate, which left a gap for a failed allocation to stop in.
    void allocate_buckets_from_shift(std::uint8_t shifts) {
        auto num_buckets = calc_num_buckets(shifts);
        if constexpr (!has_contiguous_buckets) {
            if (num_buckets < m_buckets.size()) {
                // Shrinking, which rehash does. This used to work because the caller emptied the
                // array first and the loop below then grew it from nothing; without that it would
                // keep the larger size. Shrinking rather than emptying is what keeps the array and
                // the mask agreeing at every point: it hands memory back instead of asking for it,
                // so unlike a clear-then-regrow it has no failure to stop in.
                m_buckets.resize(num_buckets);
            } else {
                if constexpr (has_reserve<bucket_container_type>) {
                    m_buckets.reserve(num_buckets);
                }
                // Growing in place leaves the old buckets where they are, so a failure part way
                // through leaves an array that is merely larger than the mask below describes,
                // which nothing reads.
                for (std::size_t i = m_buckets.size(); i < num_buckets; ++i) {
                    m_buckets.emplace_back();
                }
            }
        } else {
            // Built beside the old array rather than over it, so that a failure here leaves the
            // table exactly as it was. Callers used to give the old array back first, which made
            // this the only allocation alive -- and made a failure leave them holding values with
            // no buckets to find them by, which is not a state anything can recover from without
            // allocating again.
            auto fresh = bucket_container_type(m_buckets.get_allocator());
            fresh.resize(num_buckets + bucket_padding);
            for (std::size_t i = 0; i < bucket_padding; ++i) {
                fresh[num_buckets + i] = {sentinel_dist_and_fingerprint, sentinel_value_idx};
            }
            m_buckets = std::move(fresh);
        }
        // All three commit here, together, and only once the array they describe exists. They have
        // to move as one: do_find indexes its first probe with hash >> m_shifts and does not mask,
        // so a shift that has run ahead of the array reads past the end of it, and a mask published
        // ahead of an allocation that then failed does the same. This is the one function every
        // bucket-allocating path goes through, which is what makes a failed growth leave the old
        // buckets intact and consistent rather than unusable.
        m_shifts = shifts;
        describe_buckets(num_buckets);
    }

    // The two values derived from the bucket array's size. Only ever called once the array of that
    // size exists; see the note above.
    void describe_buckets(std::size_t num_buckets) {
        m_bucket_mask = static_cast<value_idx_type>(num_buckets - 1);
        if (num_buckets == max_bucket_count()) {
            // reached the maximum, make sure we can use each bucket
            m_max_bucket_capacity = max_bucket_count();
        } else {
            m_max_bucket_capacity = static_cast<value_idx_type>(static_cast<float>(num_buckets) * max_load_factor());
        }
    }

    // The bucket array is not allocated until the first element goes in, so that a default
    // constructed table does not allocate. Every path that probes the buckets either returns early
    // while the table is empty (do_find and do_find_hashed's callers, do_erase_key), or needs an
    // iterator into m_values and so
    // cannot be reached in this state (erase, extract, replace_key), or calls this first -- which
    // is the three insert entry points, the only ones that reach the buckets without a prior
    // emptiness check.
    void allocate_buckets_if_none() {
        if (ANKERL_UNORDERED_DENSE_UNLIKELY(m_buckets.empty()))
            ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
                allocate_buckets_from_shift(m_shifts);
                clear_buckets();
            }
    }

    void clear_buckets() {
        // Reachable now that a table can have no buckets at all -- extract() clears them on the way
        // out whether or not there are any. data() is null in that state, and memset's pointer has
        // to be valid even for a zero length. Neither sanitizer in CI objects, so this is on the
        // language rule rather than on a diagnostic.
        if (m_buckets.empty()) {
            return;
        }
        if constexpr (!has_contiguous_buckets) {
            for (auto&& e : m_buckets) {
                std::memset(&e, 0, sizeof(e));
            }
        } else {
            // bucket_count() and not the array size: the sentinels behind it stay
            std::memset(m_buckets.data(), 0, sizeof(Bucket) * bucket_count());
        }
    }

    void clear_and_fill_buckets_from_values() {
        clear_buckets();
        // Counted in std::size_t, for the reason spelled out in replace(): max_size() is exactly
        // what value_idx_type can hold, so a container of precisely that many has a size that is
        // not representable in it and the cast wraps to zero. Latent here rather than live -- a
        // table at max_size() already has the smallest shift, so rehash() and reserve() early out
        // before reaching this -- but the rule is the same and only one place was following it.
        for (std::size_t value_idx = 0, end_idx = m_values.size(); value_idx < end_idx; ++value_idx) {
            auto const& key = get_key(m_values[value_idx]);
            auto [dist_and_fingerprint, bucket] = next_while_less(key);

            // we know for certain that key has not yet been inserted, so no need to check it.
            place_and_shift_up({dist_and_fingerprint, static_cast<value_idx_type>(value_idx)}, bucket);
        }
    }

    void increase_size() {
        if (m_max_bucket_capacity == max_bucket_count()) {
            // remove the value again, we can't add it!
            m_values.pop_back();
            on_error_bucket_overflow();
        }
        // Both callers have already appended the new element to m_values, which is why the branch
        // above takes it back out before reporting the overflow. A bucket array that cannot be
        // grown is the same situation: the element is in m_values with no bucket pointing at it,
        // and never will have one, so size() would count an element that find() cannot reach.
        // Taking it back out is what makes a failed insert have no effect, which is what the
        // unordered containers promise for inserting a single element.
        if constexpr (ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS()) {
            try {
                allocate_buckets_from_shift(static_cast<std::uint8_t>(m_shifts - 1));
            } catch (...) {
                m_values.pop_back();
                throw;
            }
        } else {
            allocate_buckets_from_shift(static_cast<std::uint8_t>(m_shifts - 1));
        }
        clear_and_fill_buckets_from_values();
    }

    // Closes the hole that the erased value left in m_values, by moving the last value into it and repointing that
    // value's bucket. Runs after the erased value has been handed over, and has to run even when handing it over threw:
    // by that point the bucket is already gone, so leaving the value in place would mean size() counts an element that
    // nothing can find.
    void finish_erase(value_idx_type value_idx_to_remove) {
        if (value_idx_to_remove != m_values.size() - 1) {
            // no luck, we'll have to replace the value with the last one and update the index accordingly
            auto& val = m_values[value_idx_to_remove];
            val = std::move(m_values.back());

            // update the value index of the moved entry
            auto const values_idx_back = static_cast<value_idx_type>(m_values.size() - 1);
            auto const home = bucket_idx_from_hash(mixed_hash(get_key(val)));
            at(m_buckets, bucket_idx_of_value(home, values_idx_back)).m_value_idx = value_idx_to_remove;
        }
        m_values.pop_back();
    }

    template <typename Op>
    void do_erase(value_idx_type bucket_idx, value_idx_type value_idx_to_remove, Op handle_erased_value) {
        // both values are needed after the shift down; start fetching them now to overlap the latencies
        ANKERL_UNORDERED_DENSE_PREFETCH(&m_values[value_idx_to_remove]);
        ANKERL_UNORDERED_DENSE_PREFETCH(&m_values.back());

        erase_and_shift_down(bucket_idx);
        auto&& erased_value = std::move(m_values[value_idx_to_remove]);

        // erase() hands the value to a callback that cannot throw, so the branch below is not even instantiated for it.
        // extract() moves the value out into the caller's storage, and that move is the one that can throw.
        if constexpr (ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS() && !noexcept(handle_erased_value(std::move(erased_value)))) {
            try {
                handle_erased_value(std::move(erased_value));
            } catch (...) {
                finish_erase(value_idx_to_remove);
                throw;
            }
        } else {
            handle_erased_value(std::move(erased_value));
        }

        finish_erase(value_idx_to_remove);
    }

    template <typename K, typename Op>
    auto do_erase_key(K&& key, Op handle_erased_value) -> std::size_t { // NOLINT(cppcoreguidelines-missing-std-forward)
        if (empty()) {
            return 0;
        }

        auto r = probe(key, mixed_hash(key));
        if (!r.found) {
            return 0;
        }
        do_erase(r.bucket_idx, r.value_idx, handle_erased_value);
        return 1;
    }

    template <class K, class M>
    auto do_insert_or_assign(K&& key, M&& mapped) -> std::pair<iterator, bool> {
        auto it_isinserted = try_emplace(std::forward<K>(key), std::forward<M>(mapped));
        if (!it_isinserted.second) {
            it_isinserted.first->second = std::forward<M>(mapped);
        }
        return it_isinserted;
    }

    template <typename... Args>
    auto do_place_element(dist_and_fingerprint_type dist_and_fingerprint, value_idx_type bucket_idx, Args&&... args)
        -> std::pair<iterator, bool> {

        // emplace the new value. If that throws an exception, no harm done; index is still in a valid state
        m_values.emplace_back(std::forward<Args>(args)...);

        auto value_idx = static_cast<value_idx_type>(m_values.size() - 1);
        if (ANKERL_UNORDERED_DENSE_UNLIKELY(is_full()))
            ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
                increase_size();
            }
        else {
            place_and_shift_up({dist_and_fingerprint, value_idx}, bucket_idx);
        }

        // place element and shift up until we find an empty spot
        return {begin() + static_cast<difference_type>(value_idx), true};
    }

    template <typename K, typename... Args>
    auto do_try_emplace(K&& key, Args&&... args) -> std::pair<iterator, bool> {
        allocate_buckets_if_none();
        auto r = probe(key, mixed_hash(key));
        if (r.found) {
            return {begin() + static_cast<difference_type>(r.value_idx), false};
        }
        return do_place_element(r.dist_and_fingerprint,
                                r.bucket_idx,
                                std::piecewise_construct,
                                std::forward_as_tuple(std::forward<K>(key)),
                                std::forward_as_tuple(std::forward<Args>(args)...));
    }

    template <typename K>
    auto do_find(K const& key) -> iterator {
        if (ANKERL_UNORDERED_DENSE_UNLIKELY(empty()))
            ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
                return end();
            }

        return do_find_hashed(key, mixed_hash(key));
    }

    // Where a window of four buckets decided nothing, the next window: four buckets on, or fewer
    // where the padding was among them -- which is also where the index wraps to zero. Returns how
    // many buckets were real.
    auto next_window(value_idx_type& bucket_idx) const -> std::size_t {
        auto lanes = (std::min)(std::size_t{4}, std::size_t{m_bucket_mask} + 1 - bucket_idx);
        bucket_idx = static_cast<value_idx_type>((bucket_idx + lanes) & m_bucket_mask);
        return lanes;
    }

#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
    // NOLINTBEGIN(portability-simd-intrinsics) -- this is the x86 path, on purpose
    // One field of each of the four buckets at gp, in four lanes: field 0 is
    // m_dist_and_fingerprint, field 1 is m_value_idx.
    template <int Field>
    [[nodiscard]] static auto gather(Bucket const* gp) -> __m128i {
        auto lo = _mm_loadu_si128(reinterpret_cast<__m128i const*>(gp));     // NOLINT
        auto hi = _mm_loadu_si128(reinterpret_cast<__m128i const*>(gp + 2)); // NOLINT
        return _mm_castps_si128(
            _mm_shuffle_ps(_mm_castsi128_ps(lo), _mm_castsi128_ps(hi), _MM_SHUFFLE(2 + Field, Field, 2 + Field, Field)));
    }
    // NOLINTEND(portability-simd-intrinsics)
#    endif

    // The bucket that points at a value, searched from the value's home bucket. Every value has
    // one, so there is no other stopping condition.
    [[nodiscard]] auto bucket_idx_of_value(value_idx_type bucket_idx, value_idx_type value_idx) const -> value_idx_type {
#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
        // NOLINTBEGIN(portability-simd-intrinsics)
        if constexpr (has_simd_scan) {
            // Four at a time, matching the value index: only one bucket in the table holds it, so
            // its lane is the answer. The sentinels hold the one index a value can have only in a
            // table at max_size(), which is what the scalar walk below is left with.
            if (ANKERL_UNORDERED_DENSE_LIKELY(value_idx != sentinel_value_idx)) {
                auto const* data = m_buckets.data();
                auto const wanted = _mm_set1_epi32(static_cast<int>(value_idx));
                while (true) {
                    auto eq = static_cast<unsigned>(
                        _mm_movemask_ps(_mm_castsi128_ps(_mm_cmpeq_epi32(gather<1>(data + bucket_idx), wanted))));
                    if (ANKERL_UNORDERED_DENSE_LIKELY(eq != 0)) {
                        return static_cast<value_idx_type>(bucket_idx + detail::countr_zero(eq));
                    }
                    next_window(bucket_idx);
                }
            }
        }
        // NOLINTEND(portability-simd-intrinsics)
#    endif
        while (value_idx != at(m_buckets, bucket_idx).m_value_idx) {
            bucket_idx = next(bucket_idx);
        }
        return bucket_idx;
    }

    // Where a probe for a key stopped. Found: the bucket holding it, and the value it points to.
    // Not found: the bucket the key would be placed in, and the dist_and_fingerprint it would carry
    // there -- exactly what an insert needs next. dist_and_fingerprint is meaningful only then.
    struct probe_result {
        dist_and_fingerprint_type dist_and_fingerprint;
        value_idx_type bucket_idx;
        value_idx_type value_idx;
        bool found;
    };

    // One bucket at a time, from any point of a probe sequence.
    template <typename K>
    auto probe_scalar(K const& key, dist_and_fingerprint_type dist_and_fingerprint, value_idx_type bucket_idx) const
        -> probe_result {
        while (true) {
            auto const* bucket = &at(m_buckets, bucket_idx);
            if (dist_and_fingerprint == bucket->m_dist_and_fingerprint) {
                if (m_equal(key, get_key(m_values[bucket->m_value_idx]))) {
                    return {dist_and_fingerprint, bucket_idx, bucket->m_value_idx, true};
                }
            } else if (dist_and_fingerprint > bucket->m_dist_and_fingerprint) {
                return {dist_and_fingerprint, bucket_idx, 0, false};
            }
            dist_and_fingerprint = dist_inc(dist_and_fingerprint);
            bucket_idx = next(bucket_idx);
        }
    }

#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
    // NOLINTBEGIN(portability-simd-intrinsics) -- this is the x86 path, on purpose
    // Four consecutive buckets per step, starting at the home bucket. For each lane the
    // dist_and_fingerprint this key would have there is compared: equal is a fingerprint match
    // worth a key comparison, less is the robin hood proof that the key is absent -- and where it
    // would go. The lowest lane that is either decides, which makes the outcome independent of
    // *where* in the probe sequence it happened: one data dependent branch per probe instead of one
    // per bucket. The last three buckets of the array have no four buckets after them, and hand
    // over to the scalar probe.
    template <typename K>
    auto probe_simd(K const& key, std::uint64_t mh) const -> probe_result {
        auto dist_and_fingerprint = dist_and_fingerprint_from_hash(mh);
        auto bucket_idx = bucket_idx_from_hash(mh);
        auto const* data = m_buckets.data();

        auto expected = _mm_add_epi32(_mm_set1_epi32(static_cast<int>(dist_and_fingerprint)),
                                      _mm_setr_epi32(0,
                                                     static_cast<int>(Bucket::dist_inc),
                                                     static_cast<int>(2 * Bucket::dist_inc),
                                                     static_cast<int>(3 * Bucket::dist_inc)));
        auto const step = _mm_set1_epi32(static_cast<int>(4 * Bucket::dist_inc));

        while (true) {
            auto const* gp = data + bucket_idx;
            auto d = gather<0>(gp);

            // Two lane masks from the sign bits: bucket - expected is negative where the bucket
            // holds less (both are far below 2^31, so the difference cannot wrap), and a compare
            // for equality is all ones where they are equal. Their or has a sign bit set in every
            // lane that is either.
            auto eqv = _mm_cmpeq_epi32(d, expected);
            auto lessv = _mm_sub_epi32(d, expected);
            auto candidates = static_cast<unsigned>(_mm_movemask_ps(_mm_castsi128_ps(_mm_or_si128(eqv, lessv))));
            auto less = static_cast<unsigned>(_mm_movemask_ps(_mm_castsi128_ps(lessv)));
            if (ANKERL_UNORDERED_DENSE_LIKELY(candidates != 0)) {
                auto j = detail::countr_zero(candidates);
                auto idx = static_cast<value_idx_type>(bucket_idx + j);
                if (0 != ((less >> j) & 1U)) {
                    return {
                        static_cast<dist_and_fingerprint_type>(dist_and_fingerprint + (j * Bucket::dist_inc)), idx, 0, false};
                }
                auto value_idx = gp[j].m_value_idx;
                if (ANKERL_UNORDERED_DENSE_LIKELY(m_equal(key, get_key(m_values[value_idx])))) {
                    return {dist_and_fingerprint, idx, value_idx, true};
                }
                // A fingerprint collision. Rare enough that the scalar probe can take it from the
                // next bucket on, which also keeps the vector state from having to survive the
                // key comparison above.
                return probe_scalar(
                    key,
                    static_cast<dist_and_fingerprint_type>(dist_and_fingerprint + ((j + 1) * Bucket::dist_inc)),
                    next(idx));
            }
            // nothing decided in these four
            auto lanes = next_window(bucket_idx);
            dist_and_fingerprint = static_cast<dist_and_fingerprint_type>(dist_and_fingerprint + (lanes * Bucket::dist_inc));
            if (ANKERL_UNORDERED_DENSE_UNLIKELY(lanes != 4 || dist_and_fingerprint >=
                                                                  sentinel_dist_and_fingerprint - (4 * Bucket::dist_inc))) {
                // a wrap, or a distance the lane arithmetic could not hold: the scalar probe takes it
                return probe_scalar(key, dist_and_fingerprint, bucket_idx);
            }
            expected = _mm_add_epi32(expected, step);
        }
    }
    // NOLINTEND(portability-simd-intrinsics)
#    endif

    // The find of a configuration without the vector probe: one bucket at a time, the first two
    // unrolled. *Always* checking a few directly before entering the loop measured faster.
    template <typename K>
    auto do_find_scalar(K const& key, dist_and_fingerprint_type dist_and_fingerprint, value_idx_type bucket_idx) -> iterator {
        auto* bucket = &at(m_buckets, bucket_idx);

        if (dist_and_fingerprint == bucket->m_dist_and_fingerprint && m_equal(key, get_key(m_values[bucket->m_value_idx]))) {
            return begin() + static_cast<difference_type>(bucket->m_value_idx);
        }
        dist_and_fingerprint = dist_inc(dist_and_fingerprint);
        bucket_idx = next(bucket_idx);
        bucket = &at(m_buckets, bucket_idx);

        if (dist_and_fingerprint == bucket->m_dist_and_fingerprint && m_equal(key, get_key(m_values[bucket->m_value_idx]))) {
            return begin() + static_cast<difference_type>(bucket->m_value_idx);
        }
        dist_and_fingerprint = dist_inc(dist_and_fingerprint);
        bucket_idx = next(bucket_idx);
        bucket = &at(m_buckets, bucket_idx);

        while (true) {
            if (dist_and_fingerprint == bucket->m_dist_and_fingerprint) {
                if (m_equal(key, get_key(m_values[bucket->m_value_idx]))) {
                    return begin() + static_cast<difference_type>(bucket->m_value_idx);
                }
            } else if (dist_and_fingerprint > bucket->m_dist_and_fingerprint) {
                return end();
            }
            dist_and_fingerprint = dist_inc(dist_and_fingerprint);
            bucket_idx = next(bucket_idx);
            bucket = &at(m_buckets, bucket_idx);
        }
    }

    template <typename K>
    auto probe(K const& key, std::uint64_t mh) const -> probe_result {
#    if ANKERL_UNORDERED_DENSE_HAS_SSE2
        // An else, so that the scalar call is not merely never reached but not there at all: MSVC
        // warns about code it can prove unreachable, and this build treats warnings as errors.
        if constexpr (has_simd_scan) {
            return probe_simd(key, mh);
        } else
#    endif
        {
            return probe_scalar(key, dist_and_fingerprint_from_hash(mh), bucket_idx_from_hash(mh));
        }
    }

    // Same lookup with the hashing already done. Requires the bucket array to be allocated, which
    // !empty() implies; the callers test empty() rather than this function so that a lookup in an
    // empty table returns without hashing anything.
    template <typename K>
    auto do_find_hashed(K const& key, std::uint64_t mh) -> iterator {
        if constexpr (has_simd_scan) {
            auto r = probe(key, mh);
            return r.found ? begin() + static_cast<difference_type>(r.value_idx) : end();
        } else {
            return do_find_scalar(key, dist_and_fingerprint_from_hash(mh), bucket_idx_from_hash(mh));
        }
    }

    template <typename K>
    auto do_find(K const& key) const -> const_iterator {
        return const_cast<table*>(this)->do_find(key); // NOLINT(cppcoreguidelines-pro-type-const-cast)
    }

    template <typename K>
    auto do_find(K const& key, precomputed_hash ph) -> iterator {
        if (ANKERL_UNORDERED_DENSE_UNLIKELY(empty()))
            ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
                return end();
            }

        return do_find_hashed(key, ph.m_mixed_hash);
    }

    template <typename K>
    auto do_find(K const& key, precomputed_hash ph) const -> const_iterator {
        return const_cast<table*>(this)->do_find(key, ph); // NOLINT(cppcoreguidelines-pro-type-const-cast)
    }

    template <typename K, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto do_at(K const& key) -> Q& {
        if (auto it = find(key); ANKERL_UNORDERED_DENSE_LIKELY(end() != it))
            ANKERL_UNORDERED_DENSE_LIKELY_ATTR {
                return it->second;
            }
        on_error_key_not_found();
    }

    template <typename K, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto do_at(K const& key) const -> Q const& {
        return const_cast<table*>(this)->at(key); // NOLINT(cppcoreguidelines-pro-type-const-cast)
    }

    template <typename K, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto do_at(K const& key, precomputed_hash ph) -> Q& {
        if (auto it = find(key, ph); ANKERL_UNORDERED_DENSE_LIKELY(end() != it))
            ANKERL_UNORDERED_DENSE_LIKELY_ATTR {
                return it->second;
            }
        on_error_key_not_found();
    }

    template <typename K, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto do_at(K const& key, precomputed_hash ph) const -> Q const& {
        return const_cast<table*>(this)->do_at(key, ph); // NOLINT(cppcoreguidelines-pro-type-const-cast)
    }

public:
    explicit table(std::size_t bucket_count,
                   Hash const& hash = Hash(),
                   KeyEqual const& equal = KeyEqual(),
                   allocator_type const& alloc_or_container = allocator_type())
        : m_values(alloc_or_container)
        , m_buckets(alloc_or_container)
        , m_hash(hash)
        , m_equal(equal) {
        // No bucket_count asked for means no buckets yet: the first insert allocates them. See
        // allocate_buckets_if_none(). A default constructed table therefore costs no allocation at
        // all, so one can sit in a scope that may never use it without paying for it.
        if (0 != bucket_count) {
            reserve(bucket_count);
        }
    }

    table()
        : table(0) {}

    table(std::size_t bucket_count, allocator_type const& alloc)
        : table(bucket_count, Hash(), KeyEqual(), alloc) {}

    table(std::size_t bucket_count, Hash const& hash, allocator_type const& alloc)
        : table(bucket_count, hash, KeyEqual(), alloc) {}

    explicit table(allocator_type const& alloc)
        : table(0, Hash(), KeyEqual(), alloc) {}

    template <class InputIt>
    table(InputIt first,
          InputIt last,
          size_type bucket_count = 0,
          Hash const& hash = Hash(),
          KeyEqual const& equal = KeyEqual(),
          allocator_type const& alloc = allocator_type())
        : table(bucket_count, hash, equal, alloc) {
        insert(first, last);
    }

    template <class InputIt>
    table(InputIt first, InputIt last, size_type bucket_count, allocator_type const& alloc)
        : table(first, last, bucket_count, Hash(), KeyEqual(), alloc) {}

    template <class InputIt>
    table(InputIt first, InputIt last, size_type bucket_count, Hash const& hash, allocator_type const& alloc)
        : table(first, last, bucket_count, hash, KeyEqual(), alloc) {}

    // Asks the allocator whether it wants to come along, which is what allocator_traits' default
    // does and what an allocator like std::pmr::polymorphic_allocator declines: a copy of a map
    // living in an arena should not silently keep that arena alive and keep allocating into it.
    table(table const& other)
        : table(other,
                std::allocator_traits<allocator_type>::select_on_container_copy_construction(other.m_values.get_allocator())) {
    }

    // m_buckets takes the allocator too. Leaving it to its default member initialiser put the
    // bucket array in the default resource while the values went where the caller asked, so half
    // the container escaped the arena it was given -- and get_allocator(), which reports m_values'
    // allocator, could not be used to reason about the buckets any more.
    table(table const& other, allocator_type const& alloc)
        : m_values(other.m_values, alloc)
        , m_buckets(alloc)
        , m_max_load_factor(other.m_max_load_factor)
        , m_hash(other.m_hash)
        , m_equal(other.m_equal) {
        copy_buckets(other);
    }

    // Unconditionally noexcept, and honestly so: it hands over other's own allocator, so the
    // assignment below always takes the branch that takes the buffers over rather than the one
    // that moves elements into freshly allocated memory.
    table(table&& other) noexcept
        : table(std::move(other), other.m_values.get_allocator()) {}

    // Uses alloc, unconditionally. It used to construct empty and then move-assign, which cannot
    // express that: assignment has to consult propagate_on_container_move_assignment, so with a
    // propagating allocator this ended up holding other's and the allocator the caller asked for
    // was quietly dropped -- while std::vector, given the same allocator, kept it.
    //
    // Not unconditionally noexcept, unlike the plain move constructor above: this is the one whose
    // whole purpose is a *differing* allocator, so the containers below may have to move the
    // elements one at a time, and that allocates. The specification is theirs.
    // NOLINTNEXTLINE(cppcoreguidelines-rvalue-reference-param-not-moved) -- moved from member by member
    table(table&& other, allocator_type const& alloc) noexcept(
        std::is_nothrow_constructible_v<value_container_type, value_container_type&&, allocator_type const&> &&
        std::is_nothrow_constructible_v<bucket_container_type, bucket_container_type&&, allocator_type const&> &&
        std::is_nothrow_move_constructible_v<Hash> && std::is_nothrow_move_constructible_v<KeyEqual>)
        : m_values(std::move(other.m_values), alloc)
        , m_buckets(std::move(other.m_buckets), alloc)
        , m_max_bucket_capacity(std::exchange(other.m_max_bucket_capacity, 0))
        , m_bucket_mask(std::exchange(other.m_bucket_mask, 0))
        , m_max_load_factor(std::exchange(other.m_max_load_factor, default_max_load_factor))
        , m_hash(std::move(other.m_hash))
        , m_equal(std::move(other.m_equal))
        , m_shifts(std::exchange(other.m_shifts, initial_shifts)) {
        // When the allocators differ the two containers above moved element by element, so other
        // still holds them. Either way it has to come out of this as an empty, usable table, which
        // the exchanges above have already made the rest of it -- and an empty table needs no
        // buckets, so this hands nothing back to it.
        other.m_values.clear();
        other.m_buckets.clear();
    }

    table(std::initializer_list<value_type> ilist,
          std::size_t bucket_count = 0,
          Hash const& hash = Hash(),
          KeyEqual const& equal = KeyEqual(),
          allocator_type const& alloc = allocator_type())
        : table(bucket_count, hash, equal, alloc) {
        insert(ilist);
    }

    table(std::initializer_list<value_type> ilist, size_type bucket_count, allocator_type const& alloc)
        : table(ilist, bucket_count, Hash(), KeyEqual(), alloc) {}

    table(std::initializer_list<value_type> init, size_type bucket_count, Hash const& hash, allocator_type const& alloc)
        : table(init, bucket_count, hash, KeyEqual(), alloc) {}

    ~table() = default;

    auto operator=(table const& other) -> table& {
        if (&other != this) {
            deallocate_buckets(); // deallocate before m_values is set (might have another allocator)

            // Copying the values, and building the buckets for them, both allocate. Until both have
            // happened the table holds values with no buckets to find them by; a throw in there
            // used to leave it that way, so size() counted elements that find() could not reach and
            // the next lookup probed a bucket array that was not there. See reset_to_empty().
            if constexpr (ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS()) {
                try {
                    copy_everything_from(other);
                } catch (...) {
                    reset_to_empty();
                    throw;
                }
            } else {
                copy_everything_from(other);
            }
        }
        return *this;
    }

    // The condition used to be wrapped in another noexcept(), which asks whether evaluating a bool expression can
    // throw. It cannot, so the specification was noexcept(true) whatever the traits said, and a type with a throwing
    // move assignment terminated instead of propagating.
    auto operator=(table&& other) noexcept(move_assign_is_nothrow) -> table& {
        if (&other != this) {
            deallocate_buckets(); // deallocate before m_values is set (might have another allocator)

            // Same window as the copy assignment above, and reachable for the same reason: with an
            // allocator that neither propagates nor compares equal the move below moves the
            // elements one at a time into memory it has to allocate. See reset_to_empty().
            // Exactly when this operator does not promise noexcept, which is what makes the
            // recovery reachable rather than a rethrow inside a noexcept function.
            if constexpr (ANKERL_UNORDERED_DENSE_HAS_EXCEPTIONS() && !move_assign_is_nothrow) {
                try {
                    move_everything_from(std::move(other));
                } catch (...) {
                    reset_to_empty();
                    throw;
                }
            } else {
                move_everything_from(std::move(other));
            }
        }
        return *this;
    }

    auto operator=(std::initializer_list<value_type> ilist) -> table& {
        clear();
        insert(ilist);
        return *this;
    }

    auto get_allocator() const noexcept -> allocator_type {
        return m_values.get_allocator();
    }

    // iterators //////////////////////////////////////////////////////////////

    auto begin() noexcept -> iterator {
        return m_values.begin();
    }

    auto begin() const noexcept -> const_iterator {
        return m_values.begin();
    }

    auto cbegin() const noexcept -> const_iterator {
        return m_values.cbegin();
    }

    auto end() noexcept -> iterator {
        return m_values.end();
    }

    auto cend() const noexcept -> const_iterator {
        return m_values.cend();
    }

    auto end() const noexcept -> const_iterator {
        return m_values.end();
    }

    // capacity ///////////////////////////////////////////////////////////////

    [[nodiscard]] auto empty() const noexcept -> bool {
        return m_values.empty();
    }

    [[nodiscard]] auto size() const noexcept -> std::size_t {
        return m_values.size();
    }

    [[nodiscard]] static constexpr auto max_size() noexcept -> std::size_t {
        if constexpr ((std::numeric_limits<value_idx_type>::max)() == (std::numeric_limits<std::size_t>::max)()) {
            return std::size_t{1} << (sizeof(value_idx_type) * 8 - 1);
        } else {
            return std::size_t{1} << (sizeof(value_idx_type) * 8);
        }
    }

    // modifiers //////////////////////////////////////////////////////////////

    void clear() {
        if (!empty()) {
            m_values.clear();
            clear_buckets();
        }
    }

    auto insert(value_type const& value) -> std::pair<iterator, bool> {
        return emplace(value);
    }

    auto insert(value_type&& value) -> std::pair<iterator, bool> {
        return emplace(std::move(value));
    }

    template <class P, std::enable_if_t<std::is_constructible_v<value_type, P&&>, bool> = true>
    auto insert(P&& value) -> std::pair<iterator, bool> {
        return emplace(std::forward<P>(value));
    }

    auto insert(const_iterator /*hint*/, value_type const& value) -> iterator {
        return insert(value).first;
    }

    auto insert(const_iterator /*hint*/, value_type&& value) -> iterator {
        return insert(std::move(value)).first;
    }

    template <class P, std::enable_if_t<std::is_constructible_v<value_type, P&&>, bool> = true>
    auto insert(const_iterator /*hint*/, P&& value) -> iterator {
        return insert(std::forward<P>(value)).first;
    }

    template <class InputIt>
    void insert(InputIt first, InputIt last) {
        while (first != last) {
            insert(*first);
            ++first;
        }
    }

    void insert(std::initializer_list<value_type> ilist) {
        insert(ilist.begin(), ilist.end());
    }

    // nonstandard API: *this is emptied.
    // Also see "A Standard flat_map" https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p0429r9.pdf
    auto extract() && -> value_container_type {
        auto values = std::move(m_values);

        // Moving the values out does not empty the buckets, and they index into the container that just left. Emptying
        // them here is what makes "*this is emptied" true: without it the table looks empty -- size() is 0, find()
        // returns end() -- and then the next insert probes a bucket pointing at an element that is no longer there.
        m_values.clear();
        clear_buckets();
        return values;
    }

    // nonstandard API:
    // Discards the internally held container and replaces it with the one passed. Erases non-unique elements.
    auto replace(value_container_type&& container) {
        if (ANKERL_UNORDERED_DENSE_UNLIKELY(container.size() > max_size()))
            ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
                on_error_too_many_elements();
            }
        auto shifts = calc_shifts_for_size(container.size());
        if (0 == bucket_count() || shifts < m_shifts || container.get_allocator() != m_values.get_allocator()) {
            allocate_buckets_from_shift(shifts);
        }
        clear_buckets();

        m_values = std::move(container);

        // can't use clear_and_fill_buckets_from_values() because container elements might not be unique
        //
        // Counted in std::size_t rather than in value_idx_type. max_size() is exactly the number
        // values that type can hold, so a container of precisely that many has a size that is not
        // representable in it: the cast wrapped to zero, the loop below never ran once, and the
        // table came back reporting size() elements with no bucket pointing at any of them. Every
        // index the loop produces is representable -- it is the count that is not.
        auto value_idx = std::size_t{};

        // loop until we reach the end of the container. duplicated entries will be replaced with back().
        while (value_idx != m_values.size()) {
            auto const& key = get_key(m_values[value_idx]);
            auto r = probe(key, mixed_hash(key));
            if (r.found) {
                if (value_idx != m_values.size() - 1) {
                    m_values[value_idx] = std::move(m_values.back());
                }
                m_values.pop_back();
            } else {
                place_and_shift_up({r.dist_and_fingerprint, static_cast<value_idx_type>(value_idx)}, r.bucket_idx);
                ++value_idx;
            }
        }
    }

    template <class M, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto insert_or_assign(Key const& key, M&& mapped) -> std::pair<iterator, bool> {
        return do_insert_or_assign(key, std::forward<M>(mapped));
    }

    template <class M, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto insert_or_assign(Key&& key, M&& mapped) -> std::pair<iterator, bool> {
        return do_insert_or_assign(std::move(key), std::forward<M>(mapped));
    }

    template <typename K,
              typename M,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto insert_or_assign(K&& key, M&& mapped) -> std::pair<iterator, bool> {
        return do_insert_or_assign(std::forward<K>(key), std::forward<M>(mapped));
    }

    template <class M, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto insert_or_assign(const_iterator /*hint*/, Key const& key, M&& mapped) -> iterator {
        return do_insert_or_assign(key, std::forward<M>(mapped)).first;
    }

    template <class M, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto insert_or_assign(const_iterator /*hint*/, Key&& key, M&& mapped) -> iterator {
        return do_insert_or_assign(std::move(key), std::forward<M>(mapped)).first;
    }

    template <typename K,
              typename M,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto insert_or_assign(const_iterator /*hint*/, K&& key, M&& mapped) -> iterator {
        return do_insert_or_assign(std::forward<K>(key), std::forward<M>(mapped)).first;
    }

    // Single arguments for unordered_set can be used without having to construct the value_type
    template <class K,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<!is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto emplace(K&& key) -> std::pair<iterator, bool> {
        allocate_buckets_if_none();
        auto r = probe(key, mixed_hash(key));
        if (r.found) {
            // found it, return without ever actually creating anything
            return {begin() + static_cast<difference_type>(r.value_idx), false};
        }

        // value is new, insert element first, so when exception happens we are in a valid state
        return do_place_element(r.dist_and_fingerprint, r.bucket_idx, std::forward<K>(key));
    }

    template <class... Args>
    auto emplace(Args&&... args) -> std::pair<iterator, bool> {
        allocate_buckets_if_none();

        // we have to instantiate the value_type to be able to access the key.
        // 1. emplace_back the object so it is constructed. 2. If the key is already there, pop it later in the loop.
        auto& key = get_key(m_values.emplace_back(std::forward<Args>(args)...));
        auto r = probe(key, mixed_hash(key));
        if (r.found) {
            m_values.pop_back(); // value was already there, so get rid of it
            return {begin() + static_cast<difference_type>(r.value_idx), false};
        }

        // value is new, place the bucket and shift up until we find an empty spot
        auto value_idx = static_cast<value_idx_type>(m_values.size() - 1);
        if (ANKERL_UNORDERED_DENSE_UNLIKELY(is_full()))
            ANKERL_UNORDERED_DENSE_UNLIKELY_ATTR {
                // increase_size just rehashes all the data we have in m_values
                increase_size();
            }
        else {
            // place element and shift up until we find an empty spot
            place_and_shift_up({r.dist_and_fingerprint, value_idx}, r.bucket_idx);
        }
        return {begin() + static_cast<difference_type>(value_idx), true};
    }

    template <class... Args>
    auto emplace_hint(const_iterator /*hint*/, Args&&... args) -> iterator {
        return emplace(std::forward<Args>(args)...).first;
    }

    template <class... Args, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto try_emplace(Key const& key, Args&&... args) -> std::pair<iterator, bool> {
        return do_try_emplace(key, std::forward<Args>(args)...);
    }

    template <class... Args, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto try_emplace(Key&& key, Args&&... args) -> std::pair<iterator, bool> {
        return do_try_emplace(std::move(key), std::forward<Args>(args)...);
    }

    template <class... Args, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto try_emplace(const_iterator /*hint*/, Key const& key, Args&&... args) -> iterator {
        return do_try_emplace(key, std::forward<Args>(args)...).first;
    }

    template <class... Args, typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto try_emplace(const_iterator /*hint*/, Key&& key, Args&&... args) -> iterator {
        return do_try_emplace(std::move(key), std::forward<Args>(args)...).first;
    }

    template <
        typename K,
        typename... Args,
        typename Q = T,
        typename H = Hash,
        typename KE = KeyEqual,
        std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE> && is_neither_convertible_v<K&&, iterator, const_iterator>,
                         bool> = true>
    auto try_emplace(K&& key, Args&&... args) -> std::pair<iterator, bool> {
        return do_try_emplace(std::forward<K>(key), std::forward<Args>(args)...);
    }

    template <
        typename K,
        typename... Args,
        typename Q = T,
        typename H = Hash,
        typename KE = KeyEqual,
        std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE> && is_neither_convertible_v<K&&, iterator, const_iterator>,
                         bool> = true>
    auto try_emplace(const_iterator /*hint*/, K&& key, Args&&... args) -> iterator {
        return do_try_emplace(std::forward<K>(key), std::forward<Args>(args)...).first;
    }

    // Replaces the key at the given iterator with new_key. This does not change any other data in the underlying table, so
    // all iterators and references remain valid. However, this operation can fail if new_key already exists in the table.
    // In that case, returns {iterator to the already existing new_key, false} and no change is made.
    //
    // In the case of a set, this effectively removes the old key and inserts the new key at the same spot, which is more
    // efficient than removing the old key and inserting the new key because it avoids repositioning the last element.
    template <typename K>
    auto replace_key(iterator it, K&& new_key) -> std::pair<iterator, bool> {
        auto const new_key_hash = mixed_hash(new_key);

        // first, check if new_key already exists and return if so
        auto dist_and_fingerprint = dist_and_fingerprint_from_hash(new_key_hash);
        auto bucket_idx = bucket_idx_from_hash(new_key_hash);
        while (dist_and_fingerprint <= at(m_buckets, bucket_idx).m_dist_and_fingerprint) {
            auto const& bucket = at(m_buckets, bucket_idx);
            if (dist_and_fingerprint == bucket.m_dist_and_fingerprint &&
                m_equal(new_key, get_key(m_values[bucket.m_value_idx]))) {
                return {begin() + static_cast<difference_type>(bucket.m_value_idx), false};
            }
            dist_and_fingerprint = dist_inc(dist_and_fingerprint);
            bucket_idx = next(bucket_idx);
        }

        // const_cast is needed because iterator for the set is always const, so adding another get_key overload is not
        // feasible.
        auto& target_key = const_cast<key_type&>(get_key(*it));
        auto const old_key_bucket_idx = bucket_idx_from_hash(mixed_hash(target_key));

        // Replace the key before doing any bucket changes. If it throws, no harm done, we are still in a valid state as we
        // have not modified any buckets yet.
        target_key = std::forward<K>(new_key);

        auto const value_idx = static_cast<value_idx_type>(it - begin());

        erase_and_shift_down(bucket_idx_of_value(old_key_bucket_idx, value_idx));

        // place the new bucket
        dist_and_fingerprint = dist_and_fingerprint_from_hash(new_key_hash);
        bucket_idx = bucket_idx_from_hash(new_key_hash);
        while (dist_and_fingerprint < at(m_buckets, bucket_idx).m_dist_and_fingerprint) {
            dist_and_fingerprint = dist_inc(dist_and_fingerprint);
            bucket_idx = next(bucket_idx);
        }
        place_and_shift_up({dist_and_fingerprint, value_idx}, bucket_idx);

        return {it, true};
    }

    auto erase(iterator it) -> iterator {
        auto const value_idx_to_remove = static_cast<value_idx_type>(it - cbegin());
        auto const bucket_idx = bucket_idx_of_value(bucket_idx_from_hash(mixed_hash(get_key(*it))), value_idx_to_remove);

        // The noexcept here and on the other two erase callbacks is what keeps erase() out of do_erase()'s exception
        // guard: a call expression is noexcept only if the callee says so, an empty body is not enough.
        do_erase(bucket_idx, value_idx_to_remove, [](value_type const& /*unused*/) noexcept -> void {
        });
        return begin() + static_cast<difference_type>(value_idx_to_remove);
    }

    auto extract(iterator it) -> value_type {
        auto const value_idx_to_remove = static_cast<value_idx_type>(it - cbegin());
        auto const bucket_idx = bucket_idx_of_value(bucket_idx_from_hash(mixed_hash(get_key(*it))), value_idx_to_remove);

        auto tmp = std::optional<value_type>{};
        do_erase(bucket_idx, value_idx_to_remove, [&tmp](value_type&& val) -> void {
            tmp = std::move(val);
        });
        return std::move(tmp).value();
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto erase(const_iterator it) -> iterator {
        return erase(begin() + (it - cbegin()));
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto extract(const_iterator it) -> value_type {
        return extract(begin() + (it - cbegin()));
    }

    auto erase(const_iterator first, const_iterator last) -> iterator {
        auto const idx_first = first - cbegin();
        auto const idx_last = last - cbegin();
        auto const first_to_last = std::distance(first, last);
        auto const last_to_end = std::distance(last, cend());

        // remove elements from left to right which moves elements from the end back
        auto const mid = idx_first + (std::min)(first_to_last, last_to_end);
        auto idx = idx_first;
        while (idx != mid) {
            erase(begin() + idx);
            ++idx;
        }

        // all elements from the right are moved, now remove the last element until all done
        idx = idx_last;
        while (idx != mid) {
            --idx;
            erase(begin() + idx);
        }

        return begin() + idx_first;
    }

    auto erase(Key const& key) -> std::size_t {
        return do_erase_key(key, [](value_type const& /*unused*/) noexcept -> void {
        });
    }

    auto extract(Key const& key) -> std::optional<value_type> {
        auto tmp = std::optional<value_type>{};
        do_erase_key(key, [&tmp](value_type&& val) -> void {
            tmp = std::move(val);
        });
        return tmp;
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto erase(K&& key) -> std::size_t {
        return do_erase_key(std::forward<K>(key), [](value_type const& /*unused*/) noexcept -> void {
        });
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto extract(K&& key) -> std::optional<value_type> {
        auto tmp = std::optional<value_type>{};
        do_erase_key(std::forward<K>(key), [&tmp](value_type&& val) -> void {
            tmp = std::move(val);
        });
        return tmp;
    }

    void swap(table& other) noexcept(std::is_nothrow_swappable_v<value_container_type> &&
                                     std::is_nothrow_swappable_v<bucket_container_type> && std::is_nothrow_swappable_v<Hash> &&
                                     std::is_nothrow_swappable_v<KeyEqual>) {
        // There is no free swap() for table, so "swap(other, *this)" used to resolve to the generic std::swap: three
        // move assignments, each of which hands the moved-from table a freshly allocated set of buckets. That is three
        // allocations for an operation that needs none, and three ways to throw out of a noexcept function.
        //
        // segmented_vector has a swap of its own now, so both container choices answer the allocator
        // question the same way; see its definition for what the generic std::swap did instead.
        //
        // Calling it as a member rather than unqualified is not what fixes that -- the free swap
        // beside it is found by ADL just the same. It is so that a BucketContainer supplied from
        // some other namespace cannot quietly fall back to the three-move std::swap: every
        // container is required to have the member, none is required to have the free function.
        m_values.swap(other.m_values);
        m_buckets.swap(other.m_buckets);
        using std::swap;
        swap(m_max_bucket_capacity, other.m_max_bucket_capacity);
        swap(m_bucket_mask, other.m_bucket_mask);
        swap(m_max_load_factor, other.m_max_load_factor);
        swap(m_hash, other.m_hash);
        swap(m_equal, other.m_equal);
        swap(m_shifts, other.m_shifts);
    }

    // lookup /////////////////////////////////////////////////////////////////

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto at(key_type const& key) -> Q& {
        return do_at(key);
    }

    template <typename K,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto at(K const& key) -> Q& {
        return do_at(key);
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto at(key_type const& key) const -> Q const& {
        return do_at(key);
    }

    template <typename K,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto at(K const& key) const -> Q const& {
        return do_at(key);
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto operator[](Key const& key) -> Q& {
        return try_emplace(key).first->second;
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto operator[](Key&& key) -> Q& {
        return try_emplace(std::move(key)).first->second;
    }

    template <typename K,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto operator[](K&& key) -> Q& {
        return try_emplace(std::forward<K>(key)).first->second;
    }

    auto count(Key const& key) const -> std::size_t {
        return find(key) == end() ? 0 : 1;
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto count(K const& key) const -> std::size_t {
        return find(key) == end() ? 0 : 1;
    }

    auto find(Key const& key) -> iterator {
        return do_find(key);
    }

    auto find(Key const& key) const -> const_iterator {
        return do_find(key);
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto find(K const& key) -> iterator {
        return do_find(key);
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto find(K const& key) const -> const_iterator {
        return do_find(key);
    }

    auto contains(Key const& key) const -> bool {
        return find(key) != end();
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto contains(K const& key) const -> bool {
        return find(key) != end();
    }

    auto equal_range(Key const& key) -> std::pair<iterator, iterator> {
        auto it = do_find(key);
        return {it, it == end() ? end() : it + 1};
    }

    auto equal_range(const Key& key) const -> std::pair<const_iterator, const_iterator> {
        auto it = do_find(key);
        return {it, it == end() ? end() : it + 1};
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto equal_range(K const& key) -> std::pair<iterator, iterator> {
        auto it = do_find(key);
        return {it, it == end() ? end() : it + 1};
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto equal_range(K const& key) const -> std::pair<const_iterator, const_iterator> {
        auto it = do_find(key);
        return {it, it == end() ? end() : it + 1};
    }

    // lookup with a precomputed hash /////////////////////////////////////////

    // Looking the same key up over and over -- a handful of string literals against a map parsed
    // out of a document, say -- hashes it every time, and for a long key that hashing is most of
    // the cost of the lookup. Hashing it once instead is what hash_for() and these overloads are
    // for:
    //
    //     auto const h = map.hash_for("some-long-key"); // once
    //     auto it = map.find("some-long-key", h);       // as often as you like
    //
    // The key is still needed, because a lookup that found a bucket still has to compare keys to
    // know it found the right one. What is saved is the hashing, not the comparison.
    //
    // The number a lookup wants is the one hash_for() returns, and nothing else: it is the hasher's
    // output finalized the way a lookup finalizes it, which for most hashers is not the same number
    // the hasher gave. An integer will not convert to a precomputed_hash, which is the mistake
    // worth blocking; the value inside stays open, since a caller may want to keep or move one.
    // Every table with this hasher takes it, so one hash can serve a map and a set together, and a
    // stateless hasher makes it good for the life of the program. What it does not survive is the
    // key changing -- pass the hash of a different key and the lookup quietly finds nothing.
    //
    // Only lookups take one. Insertion never will: a lookup handed the wrong hash merely misses,
    // while an insertion handed one files the element under a probe chain it is not on, which
    // loses it for good and lets a second copy of the same key in beside it. Erase is left out for
    // a duller reason -- it hashes the moved element as well as the key, so precomputing the key's
    // hash saves it only half its hashing.
    [[nodiscard]] auto hash_for(Key const& key) const -> precomputed_hash {
        return {mixed_hash(key)};
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    [[nodiscard]] auto hash_for(K const& key) const -> precomputed_hash {
        return {mixed_hash(key)};
    }

    auto find(Key const& key, precomputed_hash ph) -> iterator {
        return do_find(key, ph);
    }

    auto find(Key const& key, precomputed_hash ph) const -> const_iterator {
        return do_find(key, ph);
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto find(K const& key, precomputed_hash ph) -> iterator {
        return do_find(key, ph);
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto find(K const& key, precomputed_hash ph) const -> const_iterator {
        return do_find(key, ph);
    }

    auto contains(Key const& key, precomputed_hash ph) const -> bool {
        return find(key, ph) != end();
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto contains(K const& key, precomputed_hash ph) const -> bool {
        return find(key, ph) != end();
    }

    auto count(Key const& key, precomputed_hash ph) const -> std::size_t {
        return find(key, ph) == end() ? 0 : 1;
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto count(K const& key, precomputed_hash ph) const -> std::size_t {
        return find(key, ph) == end() ? 0 : 1;
    }

    auto equal_range(Key const& key, precomputed_hash ph) -> std::pair<iterator, iterator> {
        auto it = do_find(key, ph);
        return {it, it == end() ? end() : it + 1};
    }

    auto equal_range(Key const& key, precomputed_hash ph) const -> std::pair<const_iterator, const_iterator> {
        auto it = do_find(key, ph);
        return {it, it == end() ? end() : it + 1};
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto equal_range(K const& key, precomputed_hash ph) -> std::pair<iterator, iterator> {
        auto it = do_find(key, ph);
        return {it, it == end() ? end() : it + 1};
    }

    template <class K, class H = Hash, class KE = KeyEqual, std::enable_if_t<is_transparent_v<H, KE>, bool> = true>
    auto equal_range(K const& key, precomputed_hash ph) const -> std::pair<const_iterator, const_iterator> {
        auto it = do_find(key, ph);
        return {it, it == end() ? end() : it + 1};
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto at(key_type const& key, precomputed_hash ph) -> Q& {
        return do_at(key, ph);
    }

    template <typename Q = T, std::enable_if_t<is_map_v<Q>, bool> = true>
    auto at(key_type const& key, precomputed_hash ph) const -> Q const& {
        return do_at(key, ph);
    }

    template <typename K,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto at(K const& key, precomputed_hash ph) -> Q& {
        return do_at(key, ph);
    }

    template <typename K,
              typename Q = T,
              typename H = Hash,
              typename KE = KeyEqual,
              std::enable_if_t<is_map_v<Q> && is_transparent_v<H, KE>, bool> = true>
    auto at(K const& key, precomputed_hash ph) const -> Q const& {
        return do_at(key, ph);
    }

    // bucket interface ///////////////////////////////////////////////////////

    auto bucket_count() const noexcept -> std::size_t { // NOLINT(modernize-use-nodiscard)
        // from the mask rather than the array, which is bucket_padding longer than it counts
        return m_buckets.empty() ? 0 : std::size_t{m_bucket_mask} + 1;
    }

    static constexpr auto max_bucket_count() noexcept -> std::size_t { // NOLINT(modernize-use-nodiscard)
        return max_size();
    }

    // hash policy ////////////////////////////////////////////////////////////

    [[nodiscard]] auto load_factor() const -> float {
        return bucket_count() ? static_cast<float>(size()) / static_cast<float>(bucket_count()) : 0.0F;
    }

    [[nodiscard]] auto max_load_factor() const -> float {
        return m_max_load_factor;
    }

    void max_load_factor(float ml) {
        // A load factor above 1 is meaningful for a container that chains, and std::unordered_map takes one. Open
        // addressing cannot use it: m_max_bucket_capacity would exceed bucket_count(), is_full() would never fire, the
        // table would fill completely, and place_and_shift_up() would then probe forever for an empty bucket that does
        // not exist. Exactly 1 is fine, because is_full() is checked after the value is appended.
        m_max_load_factor = (std::min)(ml, 1.0F);
        if (bucket_count() != max_bucket_count()) {
            m_max_bucket_capacity = static_cast<value_idx_type>(static_cast<float>(bucket_count()) * max_load_factor());
        }
    }

    void rehash(std::size_t count) {
        count = (std::min)(count, max_size());
        auto shifts = calc_shifts_for_size((std::max)(count, size()));
        if (shifts != m_shifts) {
            allocate_buckets_from_shift(shifts);
            m_values.shrink_to_fit();
            clear_and_fill_buckets_from_values();
        }
    }

    void reserve(std::size_t capa) {
        capa = (std::min)(capa, max_size());
        if constexpr (has_reserve<value_container_type>) {
            // std::deque doesn't have reserve(). Make sure we only call when available
            m_values.reserve(capa);
        }
        auto shifts = calc_shifts_for_size((std::max)(capa, size()));
        if (0 == bucket_count() || shifts < m_shifts) {
            allocate_buckets_from_shift(shifts);
            clear_and_fill_buckets_from_values();
        }
    }

    // observers //////////////////////////////////////////////////////////////

    auto hash_function() const -> hasher {
        return m_hash;
    }

    auto key_eq() const -> key_equal {
        return m_equal;
    }

    // nonstandard API: expose the underlying values container
    [[nodiscard]] auto values() const noexcept -> value_container_type const& {
        return m_values;
    }

    // non-member functions ///////////////////////////////////////////////////

    friend auto operator==(table const& a, table const& b) -> bool {
        if (&a == &b) {
            return true;
        }
        if (a.size() != b.size()) {
            return false;
        }
        for (auto const& b_entry : b) {
            auto it = a.find(get_key(b_entry));
            if constexpr (is_map_v<T>) {
                // map: check that key is here, then also check that value is the same
                if (a.end() == it || !(b_entry.second == it->second)) {
                    return false;
                }
            } else {
                // set: only check that the key is here
                if (a.end() == it) {
                    return false;
                }
            }
        }
        return true;
    }

    friend auto operator!=(table const& a, table const& b) -> bool {
        return !(a == b);
    }

    // Standard containers provide this, and generic code written as "using std::swap; swap(a, b);" needs it to find
    // the member. Without it that call lands on the generic std::swap and moves three times.
    friend void swap(table& a, table& b) noexcept(noexcept(a.swap(b))) {
        a.swap(b);
    }
};

} // namespace detail

template <class Key,
          class T,
          class Hash = hash<Key>,
          class KeyEqual = std::equal_to<Key>,
          class AllocatorOrContainer = std::allocator<std::pair<Key, T>>,
          class Bucket = bucket_type::standard,
          class BucketContainer = detail::default_container_t>
using map = detail::table<Key, T, Hash, KeyEqual, AllocatorOrContainer, Bucket, BucketContainer, false>;

template <class Key,
          class T,
          class Hash = hash<Key>,
          class KeyEqual = std::equal_to<Key>,
          class AllocatorOrContainer = std::allocator<std::pair<Key, T>>,
          class Bucket = bucket_type::standard,
          class BucketContainer = detail::default_container_t>
using segmented_map = detail::table<Key, T, Hash, KeyEqual, AllocatorOrContainer, Bucket, BucketContainer, true>;

template <class Key,
          class Hash = hash<Key>,
          class KeyEqual = std::equal_to<Key>,
          class AllocatorOrContainer = std::allocator<Key>,
          class Bucket = bucket_type::standard,
          class BucketContainer = detail::default_container_t>
using set = detail::table<Key, void, Hash, KeyEqual, AllocatorOrContainer, Bucket, BucketContainer, false>;

template <class Key,
          class Hash = hash<Key>,
          class KeyEqual = std::equal_to<Key>,
          class AllocatorOrContainer = std::allocator<Key>,
          class Bucket = bucket_type::standard,
          class BucketContainer = detail::default_container_t>
using segmented_set = detail::table<Key, void, Hash, KeyEqual, AllocatorOrContainer, Bucket, BucketContainer, true>;

#    if defined(ANKERL_UNORDERED_DENSE_PMR)

namespace pmr {

template <class Key,
          class T,
          class Hash = hash<Key>,
          class KeyEqual = std::equal_to<Key>,
          class Bucket = bucket_type::standard>
using map = detail::table<Key,
                          T,
                          Hash,
                          KeyEqual,
                          ANKERL_UNORDERED_DENSE_PMR::polymorphic_allocator<std::pair<Key, T>>,
                          Bucket,
                          detail::default_container_t,
                          false>;

template <class Key,
          class T,
          class Hash = hash<Key>,
          class KeyEqual = std::equal_to<Key>,
          class Bucket = bucket_type::standard>
using segmented_map = detail::table<Key,
                                    T,
                                    Hash,
                                    KeyEqual,
                                    ANKERL_UNORDERED_DENSE_PMR::polymorphic_allocator<std::pair<Key, T>>,
                                    Bucket,
                                    detail::default_container_t,
                                    true>;

template <class Key, class Hash = hash<Key>, class KeyEqual = std::equal_to<Key>, class Bucket = bucket_type::standard>
using set = detail::table<Key,
                          void,
                          Hash,
                          KeyEqual,
                          ANKERL_UNORDERED_DENSE_PMR::polymorphic_allocator<Key>,
                          Bucket,
                          detail::default_container_t,
                          false>;

template <class Key, class Hash = hash<Key>, class KeyEqual = std::equal_to<Key>, class Bucket = bucket_type::standard>
using segmented_set = detail::table<Key,
                                    void,
                                    Hash,
                                    KeyEqual,
                                    ANKERL_UNORDERED_DENSE_PMR::polymorphic_allocator<Key>,
                                    Bucket,
                                    detail::default_container_t,
                                    true>;

} // namespace pmr

#    endif

// deduction guides ///////////////////////////////////////////////////////////

// deduction guides for alias templates are only possible since C++20
// see https://en.cppreference.com/w/cpp/language/class_template_argument_deduction

} // namespace ANKERL_UNORDERED_DENSE_NAMESPACE
} // namespace ankerl::unordered_dense

// std extensions /////////////////////////////////////////////////////////////

namespace std { // NOLINT(cert-dcl58-cpp)

template <class Key,
          class T,
          class Hash,
          class KeyEqual,
          class AllocatorOrContainer,
          class Bucket,
          class Pred,
          class BucketContainer,
          bool IsSegmented>
// NOLINTNEXTLINE(cert-dcl58-cpp)
auto erase_if(
    ankerl::unordered_dense::detail::table<Key, T, Hash, KeyEqual, AllocatorOrContainer, Bucket, BucketContainer, IsSegmented>&
        map,
    Pred pred) -> std::size_t {
    using map_t = ankerl::unordered_dense::detail::
        table<Key, T, Hash, KeyEqual, AllocatorOrContainer, Bucket, BucketContainer, IsSegmented>;

    // going back to front because erase() invalidates the end iterator
    auto const old_size = map.size();
    auto idx = old_size;
    while (idx) {
        --idx;
        auto it = map.begin() + static_cast<typename map_t::difference_type>(idx);
        if (pred(*it)) {
            map.erase(it);
        }
    }

    return old_size - map.size();
}

} // namespace std

#endif
#endif
