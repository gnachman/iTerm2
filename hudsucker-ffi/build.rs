use std::env;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();

    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_language(cbindgen::Language::C)
        .with_pragma_once(true)
        .with_include_guard("HUDSUCKER_FFI_H")
        .with_no_includes()
        .with_sys_include("stdint.h")
        .with_sys_include("stdbool.h")
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file("hudsucker_ffi.h");
}