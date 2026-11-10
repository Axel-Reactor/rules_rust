# Rust rules

The core Rust rules for building and testing libraries, binaries, and procedural
macros. Each rule is documented on its own page; this page is an overview of what
each rule does and when to use it.

All rules are loadable from `@rules_rust//rust:defs.bzl` or from their individual
`.bzl` file (e.g. `@rules_rust//rust:rust_binary.bzl`). Loading from the
individual file is preferred for new code.

## Core rules

The rules below are the primary entry points for compiling Rust code. They map
directly to the crate types Cargo produces.

- [rust_binary](./rust_binary.md) — Build a Rust executable (`--crate-type=bin`).
- [rust_library](./rust_library.md) — Build an `rlib` (`--crate-type=lib`) that
  other Rust targets can depend on.
- [rust_static_library](./rust_static_library.md) — Build a `staticlib`
  (`--crate-type=staticlib`) for linking Rust code into a C/C++ binary.
- [rust_cdylib_library](./rust_cdylib_library.md) — Build a `cdylib`
  (`--crate-type=cdylib`) for use as a shared library from C/C++ or other
  languages.
- [rust_dylib_library](./rust_dylib_library.md) — Build a `dylib`
  (`--crate-type=dylib`) for use as a shared library with the unstable Rust ABI.
- [rust_shared_library](./rust_shared_library.md) — Convenience alias over
  `rust_cdylib_library`.
- [rust_proc_macro](./rust_proc_macro.md) — Build a procedural macro crate
  (`--crate-type=proc-macro`) that other Rust targets can consume as a compile-time
  plugin.
- [rust_test](./rust_test.md) — Compile and run a Rust test binary. Can wrap a
  `rust_library`/`rust_binary` (via `crate = ...`) to run its inline `#[test]`s,
  or compile a standalone test binary from its own `srcs`.

## C++ runtime linkage

Rust link rules expose `cc_runtime_linkage = "auto" | "static" | "dynamic"`.
The default, `auto`, follows the **configured Rust standard-library linkage**
for the current link:

| Rust std selection | C++ toolchain runtime in `auto` |
| --- | --- |
| Static (the default for binaries and tests) | Static |
| Dynamic (`link_std_dylib = True` or the toolchain setting) | Dynamic, falling back to static if that is all the toolchain supplies |

Use `link_std_dylib = True` on binaries, tests, Rust ABI dylibs, or doctests to
select dynamic Rust std and default to a dynamic C++ runtime together. For a
build-wide default, use
`--@rules_rust//rust/settings:experimental_link_std_dylib=true`. The effective
Rust std setting is the target flag OR the toolchain setting; a target's `False`
does not override a build-wide `True`. Arbitrary `rustc_flags` are not interpreted
as linkage policy.

Set `cc_runtime_linkage` explicitly when the C++ runtime needs a different
policy. For example:

```python
rust_binary(
    name = "app",
    srcs = ["main.rs"],
    link_std_dylib = True,
    cc_runtime_linkage = "static",  # Override only the C++ runtime selection.
)
```

The attribute also accepts `select()` for platform-specific policies. An explicit
`dynamic` request fails when the toolchain supplies only static runtime libraries;
use `auto` to allow that fallback. A toolchain with no explicit runtime libraries
continues to rely on its own linker configuration.

This policy applies to binaries, tests, Rust and C ABI shared libraries,
procedural macros, and doctests. Archives retain static runtime inputs; their
consumers select the final link policy. Doctests select their own policy rather
than inheriting attributes from the documented target. A Rust dylib dependency
does not by itself change the consumer's selection: configure each final link.

**Default change for shared libraries:** `rust_cdylib_library` (and its
`rust_shared_library` alias) previously selected a dynamic C++ runtime regardless
of Rust std linkage. With `auto`, static Rust std selects a static C++ runtime.
Use `cc_runtime_linkage = "dynamic"` to retain the previous selection. Rust ABI
dylibs default to dynamic Rust std, so their default C++ selection stays dynamic.

The guarantee is limited to selecting the runtime libraries supplied by the C++
toolchain. Ordinary native dependencies keep their existing linkage policy.
Selection does not inspect symbols to determine whether the program needs a
C++ runtime; supplying dynamic runtime libraries can add loader dependencies even
for pure Rust code. It does not change runtimes embedded in prebuilt dependencies,
control libraries loaded at runtime, or guarantee one C++ runtime or unwinder per
process. Projects remain responsible for choosing compatible Rust and C++
toolchains and deploying any required shared libraries.

## Additional rules

Non-core rules that ship in the same ruleset:

- [rust_library_group](./rust_library_group.md) — Group several `rust_library`
  targets so they can be depended on as a single unit without generating an
  intermediate `rlib`.
- [rust_lint_config](./rust_lint_config.md) — Declare a reusable set of `rustc`,
  `clippy`, and `rustdoc` lint levels that can be attached to other rules via
  their `lint_config` attribute.
- [rust_test_suite](./rust_test_suite.md) — Convenience macro that expands into
  one `rust_test` per source file, sharing a common set of dependencies. Useful
  for `tests/**.rs` layouts that mirror Cargo's integration-test directory.

## Related pages

Rules that layer on top of the core rules live on their own pages:

- [rustdoc](./rustdoc.md) — Generate and test Rust documentation.
- [clippy](./clippy.md) — Run [Clippy](https://github.com/rust-lang/rust-clippy)
  over Rust targets.
- [rustfmt](./rustfmt.md) — Run [rustfmt](https://github.com/rust-lang/rustfmt)
  over Rust targets.
- [unpretty](./unpretty.md) — Emit `rustc -Zunpretty=...` output for a crate.
- [cargo](./cargo.md) — `cargo_build_script` and related Cargo-compatibility rules.
- [rust_analyzer](./rust_analyzer.md) — Generate a `rust-project.json` file for
  the [rust-analyzer](https://rust-analyzer.github.io) IDE server.
- [Rust Toolchains](./rust_toolchains.md) — Declare and register Rust toolchains.
