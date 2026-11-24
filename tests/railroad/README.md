# Railroad diagram fixtures

Reference output from the Rust `railroad_dsl` library (railroad crate 0.3.12)
that the Swift port must reproduce byte for byte.

- `dsl/ex_*.dsl`: the examples shipped with railroad_dsl.
- `dsl/re_*.regex` and `dsl/re_*.dsl`: regexes and the DSL that
  `ICURegexToRailroadConverter` produces for them.
- `svg/*.svg`: the SVG the Rust library renders for each DSL, with the light theme.
- `light.css`, `dark.css`: the stylesheets returned by `railroad_dsl_css_for_theme`.

`capture-golden.swift` regenerates them. It links against the Rust dylib, so it
only works on a checkout that still has `ThirdParty/librailroad_dsl`:

    swiftc -O tests/railroad/capture-golden.swift \
        sources/RegexVisualization/ICURegexToRailroadConverter.swift \
        -LThirdParty/librailroad_dsl/lib -lrailroad_dsl \
        -Xlinker -rpath -Xlinker ThirdParty/librailroad_dsl/lib -o /tmp/golden
    /tmp/golden file tests/railroad/dsl/ex_00_the-answer.dsl
    /tmp/golden regex 'a|b' /tmp/out.dsl
    /tmp/golden css dark
