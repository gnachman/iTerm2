# fish OSC 7 suppression - fish 3.x manual test

`suppression_test.py` drives the real assembled
`Resources/shell_integration/iterm2_shell_integration.fish` in a pty and asserts, for
both install orders (manual `config.fish` and the injected `vendor_conf.d` loader),
that:

- the native fish OSC 7 emitter is silenced after startup (no `file://` OSC 7 lacking
  `?machineID=` during two `cd`s), and
- our machineID-bearing OSC 7 is emitted on each prompt.

## Why this is separate from tools/test_shell_integration_encoders.sh

The encoder suite is hermetic and runs against whatever `fish` is on `PATH` (normally
4.x). The regression this guards against only reproduces on **fish 3.x**, where
`__fish_config_interactive` defines `__update_cwd_osc` **unconditionally** (no
`functions --query` guard). On 3.x, a stub installed at source time (manual install,
before the first prompt) is clobbered when fish later defines its emitter; the fix is a
one-shot `fish_prompt` handler that re-shadows after that definition, plus the inline
shadow that covers the loader order. `tools/test_shell_integration_encoders.sh` has a
`fish-loader-order` row that catches the loader-order case on any fish on `PATH`, but
the full manual-order check needs a real 3.x binary, which CI does not build.

## Building a fish 3.x binary (macOS, recent Xcode)

fish 3.x is C++ (4.x is the Rust rewrite). On a current SDK it needs three tweaks:

```sh
curl -fsSL -o fish-3.7.1.tar.xz \
  https://github.com/fish-shell/fish-shell/releases/download/3.7.1/fish-3.7.1.tar.xz
tar xf fish-3.7.1.tar.xz && cd fish-3.7.1

# 1) C++17 (libc++ headers no longer parse under C++11)
sed -i '' 's/set(CMAKE_CXX_STANDARD 11)/set(CMAKE_CXX_STANDARD 17)/' CMakeLists.txt
# 2) fish's __fallthrough__ macro collides with libc++'s [[__fallthrough__]]
#    (build/config.h defines it; the empty #else branch is compatible)
# 3) drop the test target (reserved name under newer cmake) and its stray reference
sed -i '' 's#^include(cmake/Tests.cmake)#\# &#' CMakeLists.txt
perl -0pi -e 's/set_property\(TARGET build_fish_pc CHECK-FISH-BUILD-VERSION-FILE\n\s*tests_buildroot_target\n\s*PROPERTY FOLDER cmake\/InstallTargets\)/# removed for local build/' cmake/Install.cmake

cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_DOCS=OFF -DWITH_GETTEXT=OFF
# neutralize the __fallthrough__ macro now that config.h is generated
perl -0pi -e 's/#if __has_attribute\(fallthrough\)\n#define __fallthrough__ __attribute__ \(\(fallthrough\)\);\n#else\n#define __fallthrough__\n#endif/#define __fallthrough__/' build/config.h
# a couple of defaulted move-ops need their noexcept reconciled with the header
perl -i -pe 's/autoload_t::autoload_t\(autoload_t &&\) noexcept = default;/autoload_t::autoload_t(autoload_t \&\&) = default;/' src/autoload.cpp
perl -i -pe 's/completion_t::completion_t\(completion_t &&\) = default;/completion_t::completion_t(completion_t \&\&) noexcept = default;/; s/completion_t &completion_t::operator=\(completion_t &&\) = default;/completion_t \&completion_t::operator=(completion_t \&\&) noexcept = default;/' src/complete.cpp

ninja -C build fish
```

## Running

```sh
# Point it at your fish 3.x build (or any fish binary):
FISH=/path/to/fish-3.7.1/build/fish python3 tests/fish3-osc7-suppression/suppression_test.py
# or
python3 tests/fish3-osc7-suppression/suppression_test.py /path/to/fish
```

Expected on a Mac (both orders): `PASS`, with 0 native leaks during the cd's, >=2
machineID reports, and at most one startup run-once bare OSC 7. Run it against the
UN-fixed script and the manual order fails on fish 3.x with a native leak per `cd`.
