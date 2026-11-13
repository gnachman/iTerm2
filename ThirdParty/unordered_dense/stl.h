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

#ifndef ANKERL_STL_H
#define ANKERL_STL_H

#include <array>            // for array
#include <cstdint>          // for uint64_t, uint32_t, std::uint8_t, UINT64_C
#include <cstring>          // for size_t, memcpy, memset
#include <functional>       // for equal_to, hash
#include <initializer_list> // for initializer_list
#include <iterator>         // for pair, distance
#include <limits>           // for numeric_limits
#include <memory>           // for allocator, allocator_traits, shared_ptr
#include <optional>         // for optional
#include <stdexcept>        // for out_of_range
#include <string>           // for basic_string
#include <string_view>      // for basic_string_view, hash
#include <tuple>            // for forward_as_tuple
#include <type_traits>      // for enable_if_t, declval, conditional_t, ena...
#include <utility>          // for forward, exchange, pair, as_const, piece...
#include <vector>           // for vector

// <memory_resource> includes <mutex>, which fails to compile if
// targeting GCC >= 13 with the (rewritten) win32 thread model, and
// targeting Windows earlier than Vista (0x600).  GCC predefines
// _REENTRANT when using the 'posix' model, and doesn't when using the
// 'win32' model.
#if defined __MINGW64__ && defined __GNUC__ && __GNUC__ >= 13 && !defined _REENTRANT
// _WIN32_WINNT is guaranteed to be defined here because of the
// <cstdint> inclusion above.
#    ifndef _WIN32_WINNT
#        error "_WIN32_WINNT not defined"
#    endif
#    if _WIN32_WINNT < 0x600
#        define ANKERL_MEMORY_RESOURCE_IS_BAD() 1 // NOLINT(cppcoreguidelines-macro-usage)
#    endif
#endif
#ifndef ANKERL_MEMORY_RESOURCE_IS_BAD
#    define ANKERL_MEMORY_RESOURCE_IS_BAD() 0 // NOLINT(cppcoreguidelines-macro-usage)
#endif

#if defined(__has_include) && !defined(ANKERL_UNORDERED_DENSE_DISABLE_PMR)
#    if __has_include(<memory_resource>) && !ANKERL_MEMORY_RESOURCE_IS_BAD()
#        define ANKERL_UNORDERED_DENSE_PMR std::pmr // NOLINT(cppcoreguidelines-macro-usage)
#        include <memory_resource>                  // for polymorphic_allocator
#    elif __has_include(<experimental/memory_resource>)
#        define ANKERL_UNORDERED_DENSE_PMR std::experimental::pmr // NOLINT(cppcoreguidelines-macro-usage)
#        include <experimental/memory_resource>                   // for polymorphic_allocator
#    endif
#endif

#if defined(_MSC_VER) && defined(_M_X64)
#    include <intrin.h>
#    if !defined(_M_ARM64EC)
#        pragma intrinsic(_umul128)
#    endif
#endif

#endif
