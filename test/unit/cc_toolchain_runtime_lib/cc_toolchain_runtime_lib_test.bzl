"""
Tests for handling of cc_toolchain's static_runtime_lib/dynamic_runtime_lib.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:cc_toolchain_config_lib.bzl", "feature")
load("@rules_cc//cc:defs.bzl", "cc_import", "cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
load("//rust:defs.bzl", "rust_binary", "rust_doc_test", "rust_dylib_library", "rust_library", "rust_shared_library", "rust_static_library")

def _test_cc_config_impl(ctx):
    config_info = cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "test-cc-toolchain",
        host_system_name = "unknown",
        target_system_name = "unknown",
        target_cpu = "unknown",
        target_libc = "unknown",
        compiler = "unknown",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        features = [
            feature(name = "static_link_cpp_runtimes", enabled = True),
        ],
    )
    return config_info

test_cc_config = rule(
    implementation = _test_cc_config_impl,
    provides = [CcToolchainConfigInfo],
)

def _with_extra_toolchain_transition_impl(_settings, attr):
    return {"//command_line_option:extra_toolchains": [attr.extra_toolchain]}

with_extra_toolchain_transition = transition(
    implementation = _with_extra_toolchain_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:extra_toolchains"],
)

DepActionsInfo = provider(
    "Contains information about dependencies actions.",
    fields = {
        "actions": "List[Action]",
        "runfiles": "List[File]",
    },
)

def _with_extra_toolchain_impl(ctx):
    return [
        DepActionsInfo(
            actions = ctx.attr.target[0].actions,
            runfiles = ctx.attr.target[0][DefaultInfo].default_runfiles.files.to_list(),
        ),
    ]

with_extra_toolchain = rule(
    implementation = _with_extra_toolchain_impl,
    attrs = {
        "extra_toolchain": attr.label(),
        "target": attr.label(cfg = with_extra_toolchain_transition),
    },
)

def _inputs_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    matching_actions = [action for action in tut[DepActionsInfo].actions if action.mnemonic == ctx.attr.mnemonic]
    asserts.equals(env, 1, len(matching_actions))
    if not matching_actions:
        return analysistest.end(env)
    action = matching_actions[0]
    inputs = action.inputs.to_list()
    for expected in ctx.attr.expected_inputs:
        asserts.true(
            env,
            any([input.path.endswith("/" + expected) for input in inputs]),
            "error: expected '{}' to be in inputs: '{}'".format(expected, inputs),
        )

    for unexpected in ctx.attr.unexpected_inputs:
        asserts.false(
            env,
            any([input.path.endswith("/" + unexpected) for input in inputs]),
            "error: did not expect '{}' in inputs: '{}'".format(unexpected, inputs),
        )

    for expected in ctx.attr.expected_link_arg_inputs:
        asserts.true(
            env,
            any([arg.startswith("-Clink-arg=") and arg.endswith("/" + expected) for arg in action.argv]),
            "error: expected '{}' to be linked via -Clink-arg: '{}'".format(expected, action.argv),
        )

    for expected in ctx.attr.expected_link_inputs:
        asserts.true(
            env,
            any([arg.endswith("/" + expected) for arg in action.argv]),
            "error: expected '{}' in link args: '{}'".format(expected, action.argv),
        )

    for expected in ctx.attr.expected_args:
        asserts.true(
            env,
            expected in action.argv,
            "error: expected '{}' in args: '{}'".format(expected, action.argv),
        )

    for unexpected in ctx.attr.unexpected_args:
        asserts.false(
            env,
            unexpected in action.argv,
            "error: did not expect '{}' in args: '{}'".format(unexpected, action.argv),
        )

    runfiles = tut[DepActionsInfo].runfiles
    for expected in ctx.attr.expected_runfiles:
        asserts.true(
            env,
            any([runfile.path.endswith("/" + expected) for runfile in runfiles]),
            "error: expected '{}' to be in runfiles: '{}'".format(expected, runfiles),
        )

    for unexpected in ctx.attr.unexpected_runfiles:
        asserts.false(
            env,
            any([runfile.path.endswith("/" + unexpected) for runfile in runfiles]),
            "error: did not expect '{}' in runfiles: '{}'".format(unexpected, runfiles),
        )

    for prefix in ctx.attr.expected_solib_runfile_prefixes:
        asserts.true(
            env,
            any([runfile.short_path.startswith("_solib_") and runfile.basename.startswith(prefix) for runfile in runfiles]),
            "error: expected solib runfile starting with '{}': '{}'".format(prefix, runfiles),
        )

    return analysistest.end(env)

inputs_analysis_test = analysistest.make(
    impl = _inputs_analysis_test_impl,
    doc = """An analysistest to examine the inputs of a library target.""",
    attrs = {
        "mnemonic": attr.string(default = "Rustc"),
        "expected_inputs": attr.string_list(),
        "expected_args": attr.string_list(),
        "expected_link_arg_inputs": attr.string_list(),
        "expected_link_inputs": attr.string_list(),
        "expected_runfiles": attr.string_list(),
        "expected_solib_runfile_prefixes": attr.string_list(),
        "unexpected_args": attr.string_list(),
        "unexpected_inputs": attr.string_list(),
        "unexpected_runfiles": attr.string_list(),
    },
)

def _rustdoc_link_args_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)

    actions = tut[DepActionsInfo].actions
    action = None
    for candidate in actions:
        if candidate.mnemonic == "RustdocTest":
            action = candidate
            break

    asserts.true(
        env,
        action != None,
        "error: no rustdoc test action found among: {}".format(
            [candidate.mnemonic for candidate in actions],
        ),
    )

    if action:
        for expected in ctx.attr.expected_link_arg_inputs:
            asserts.true(
                env,
                any([arg.startswith("-Clink-arg=") and arg.endswith("/" + expected) for arg in action.argv]),
                "error: expected '{}' to be linked via -Clink-arg: '{}'".format(expected, action.argv),
            )

    if action and ctx.attr.expected_any_of:
        # Any one of the accepted spellings is enough: `rustdoc.bzl` omits the
        # `-l` prefix when the target ABI is msvc, where link.exe takes bare
        # library names.
        asserts.true(
            env,
            any([expected in action.argv for expected in ctx.attr.expected_any_of]),
            "error: expected one of {} in the rustdoc test link args: '{}'".format(
                ctx.attr.expected_any_of,
                action.argv,
            ),
        )

    return analysistest.end(env)

rustdoc_link_args_analysis_test = analysistest.make(
    impl = _rustdoc_link_args_analysis_test_impl,
    doc = """An analysistest to examine the link args of a rust_doc_test target.

    rustdoc drives the doc test link itself rather than running a Bazel C++
    link action, so the cc_toolchain's runtime libs never arrive through
    `static_link_cpp_runtimes` the way they do for a rust_library. They have to
    be named explicitly on the rustdoc command line instead, or the doc test
    fails to link against a toolchain that supplies its own unwinder.
    """,
    attrs = {
        "expected_any_of": attr.string_list(),
        "expected_link_arg_inputs": attr.string_list(),
    },
)

def runtime_libs_test(name):
    """Produces test shared and static library targets that are set up to use a custom cc_toolchain with custom runtime libs.

    Args:
      name: The name of the test target.
    """

    test_cc_config(
        name = "%s/cc_toolchain_config" % name,
    )
    cc_toolchain(
        name = "%s/test_cc_toolchain_impl" % name,
        all_files = ":empty",
        compiler_files = ":empty",
        dwp_files = ":empty",
        linker_files = ":empty",
        objcopy_files = ":empty",
        strip_files = ":empty",
        supports_param_files = 0,
        toolchain_config = ":%s/cc_toolchain_config" % name,
        toolchain_identifier = "dummy_wasm32_cc",
        static_runtime_lib = ":dummy.a",
        dynamic_runtime_lib = ":dummy.so",
    )
    native.toolchain(
        name = "%s/test_cc_toolchain" % name,
        toolchain = ":%s/test_cc_toolchain_impl" % name,
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    cc_toolchain(
        name = "%s/static_only_cc_toolchain_impl" % name,
        all_files = ":empty",
        compiler_files = ":empty",
        dwp_files = ":empty",
        linker_files = ":empty",
        objcopy_files = ":empty",
        strip_files = ":empty",
        supports_param_files = 0,
        toolchain_config = ":%s/cc_toolchain_config" % name,
        toolchain_identifier = "static_only_cc",
        static_runtime_lib = ":dummy.a",
        dynamic_runtime_lib = ":empty_runtime",
    )
    native.filegroup(name = "empty_runtime", srcs = [])
    native.toolchain(
        name = "%s/static_only_cc_toolchain" % name,
        toolchain = ":%s/static_only_cc_toolchain_impl" % name,
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    rust_shared_library(
        name = "%s/__shared_library" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        tags = ["manual", "nobuild"],
    )

    with_extra_toolchain(
        name = "%s/_shared_library" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__shared_library" % name,
        tags = ["manual"],
    )

    inputs_analysis_test(
        name = "%s/shared_library" % name,
        target_under_test = "%s/_shared_library" % name,
        expected_inputs = ["dummy.so"],
        expected_args = select({
            "@platforms//os:windows": ["-ldylib=dummy"],
            "//conditions:default": [],
        }),
        expected_link_arg_inputs = select({
            "@platforms//os:windows": [],
            "//conditions:default": ["dummy.so"],
        }),
        expected_runfiles = ["dummy.so"],
        unexpected_args = select({
            "@platforms//os:windows": [],
            "//conditions:default": ["-ldylib=dummy"],
        }),
    )

    # A binary that links a Rust ABI dylib must share the dylib's dynamic C++
    # runtime instead of embedding a second, static copy.
    rust_dylib_library(
        name = "%s/__dylib_dep" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        tags = ["manual", "nobuild"],
    )

    rust_binary(
        name = "%s/__binary_with_dylib_dep" % name,
        edition = "2018",
        srcs = ["main.rs"],
        link_std_dylib = True,
        deps = [":%s/__dylib_dep" % name],
        tags = ["manual", "nobuild"],
    )

    with_extra_toolchain(
        name = "%s/_binary_with_dylib_dep" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__binary_with_dylib_dep" % name,
        tags = ["manual"],
    )

    inputs_analysis_test(
        name = "%s/binary_with_dylib_dep" % name,
        target_under_test = "%s/_binary_with_dylib_dep" % name,
        expected_inputs = ["dummy.so"],
        expected_link_arg_inputs = select({
            "@platforms//os:windows": [],
            "//conditions:default": ["dummy.so"],
        }),
        expected_runfiles = ["dummy.so"],
        unexpected_inputs = ["dummy.a"],
        target_compatible_with = select({
            "@platforms//os:linux": [],
            "@platforms//os:macos": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    # Linking libstd dynamically loads a Rust dylib too, even without any
    # dylib crates in the dependency graph.
    rust_binary(
        name = "%s/__binary_with_std_dylib" % name,
        edition = "2018",
        srcs = ["main.rs"],
        link_std_dylib = True,
        tags = ["manual", "nobuild"],
    )

    with_extra_toolchain(
        name = "%s/_binary_with_std_dylib" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__binary_with_std_dylib" % name,
        tags = ["manual"],
    )

    inputs_analysis_test(
        name = "%s/binary_with_std_dylib" % name,
        target_under_test = "%s/_binary_with_std_dylib" % name,
        expected_inputs = ["dummy.so"],
        expected_link_arg_inputs = ["dummy.so"],
        expected_runfiles = ["dummy.so"],
        unexpected_inputs = ["dummy.a"],
        target_compatible_with = select({
            "@platforms//os:linux": [],
            "@platforms//os:macos": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    # Exercise the dependency-graph branch independently of prefer-dynamic.
    rust_library(
        name = "%s/__intermediate" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        deps = [":%s/__dylib_dep" % name],
        tags = ["manual", "nobuild"],
    )
    rust_binary(
        name = "%s/__transitive_dylib" % name,
        edition = "2018",
        srcs = ["main.rs"],
        deps = [":%s/__intermediate" % name],
        tags = ["manual", "nobuild"],
    )
    with_extra_toolchain(
        name = "%s/_transitive_dylib" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__transitive_dylib" % name,
        tags = ["manual"],
    )
    inputs_analysis_test(
        name = "%s/transitive_dylib" % name,
        target_under_test = "%s/_transitive_dylib" % name,
        expected_inputs = ["dummy.so"],
        expected_link_arg_inputs = ["dummy.so"],
        expected_runfiles = ["dummy.so"],
        unexpected_inputs = ["dummy.a"],
        target_compatible_with = select({
            "@platforms//os:linux": [],
            "@platforms//os:macos": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    # Supply both forms of an ordinary native dependency. Selecting a dynamic
    # runtime must not also change this dependency to dynamic linkage.
    native.genrule(
        name = "%s/native_libraries" % name,
        outs = ["libnative.a", "libnative.so"],
        cmd = "touch $(OUTS)",
        tags = ["manual"],
    )
    cc_import(
        name = "%s/native_dep" % name,
        static_library = ":libnative.a",
        shared_library = ":libnative.so",
        tags = ["manual"],
    )
    rust_binary(
        name = "%s/__cc_common_binary" % name,
        edition = "2018",
        srcs = ["main.rs"],
        link_std_dylib = True,
        experimental_use_cc_common_link = 1,
        deps = [":%s/native_dep" % name],
        tags = ["manual", "nobuild"],
    )
    for suffix, toolchain, dynamic in [
        ("cc_common_dynamic", "test_cc_toolchain", True),
        ("cc_common_static_only", "static_only_cc_toolchain", False),
    ]:
        with_extra_toolchain(
            name = "%s/_%s" % (name, suffix),
            extra_toolchain = ":%s/%s" % (name, toolchain),
            target = "%s/__cc_common_binary" % name,
            tags = ["manual"],
        )
        inputs_analysis_test(
            name = "%s/%s" % (name, suffix),
            target_under_test = "%s/_%s" % (name, suffix),
            mnemonic = "CppLink",
            expected_inputs = ["libnative.a"] + (["dummy.so"] if dynamic else ["dummy.a"]),
            expected_link_inputs = ["libnative.a"] + ([] if dynamic else ["dummy.a"]),
            expected_runfiles = ["dummy.so"] if dynamic else [],
            expected_solib_runfile_prefixes = ["libstd-"],
            unexpected_inputs = ["libnative.so"] + (["dummy.a"] if dynamic else ["dummy.so"]),
            unexpected_runfiles = [] if dynamic else ["dummy.a", "dummy.so"],
            target_compatible_with = select({
                "@platforms//os:linux": [],
                "@platforms//os:macos": [],
                "//conditions:default": ["@platforms//:incompatible"],
            }),
        )

    with_extra_toolchain(
        name = "%s/_static_only_binary" % name,
        extra_toolchain = ":%s/static_only_cc_toolchain" % name,
        target = "%s/__binary_with_std_dylib" % name,
        tags = ["manual"],
    )
    inputs_analysis_test(
        name = "%s/static_only_binary" % name,
        target_under_test = "%s/_static_only_binary" % name,
        expected_inputs = ["dummy.a"],
        expected_args = ["-lstatic=dummy"],
        unexpected_inputs = ["dummy.so"],
        unexpected_runfiles = ["dummy.a", "dummy.so"],
    )

    with_extra_toolchain(
        name = "%s/_static_only_shared_library" % name,
        extra_toolchain = ":%s/static_only_cc_toolchain" % name,
        target = "%s/__shared_library" % name,
        tags = ["manual"],
    )
    inputs_analysis_test(
        name = "%s/static_only_shared_library" % name,
        target_under_test = "%s/_static_only_shared_library" % name,
        expected_inputs = ["dummy.a"],
        expected_args = ["-lstatic=dummy"],
        unexpected_inputs = ["dummy.so"],
        unexpected_runfiles = ["dummy.a", "dummy.so"],
    )

    rust_shared_library(
        name = "%s/__static_override" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        cc_runtime_linkage = "static",
        tags = ["manual", "nobuild"],
    )
    with_extra_toolchain(
        name = "%s/_static_override" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__static_override" % name,
        tags = ["manual"],
    )
    inputs_analysis_test(
        name = "%s/static_override" % name,
        target_under_test = "%s/_static_override" % name,
        expected_inputs = ["dummy.a"],
        expected_args = ["-lstatic=dummy"],
        unexpected_inputs = ["dummy.so"],
        unexpected_runfiles = ["dummy.a", "dummy.so"],
    )

    # Doctests of a crate that depends on a Rust dylib link like a binary
    # that depends on it.
    rust_library(
        name = "%s/__doctest_library_with_dylib_dep" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        deps = [":%s/__dylib_dep" % name],
        tags = ["manual", "nobuild"],
    )

    rust_doc_test(
        name = "%s/__doc_test_with_dylib_dep" % name,
        crate = ":%s/__doctest_library_with_dylib_dep" % name,
        tags = ["manual", "nobuild"],
    )

    with_extra_toolchain(
        name = "%s/_doc_test_with_dylib_dep" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__doc_test_with_dylib_dep" % name,
        tags = ["manual"],
        testonly = True,
    )

    rustdoc_link_args_analysis_test(
        name = "%s/doc_test_with_dylib_dep" % name,
        target_under_test = "%s/_doc_test_with_dylib_dep" % name,
        expected_link_arg_inputs = ["dummy.so"],
        target_compatible_with = select({
            "@platforms//os:linux": [],
            "@platforms//os:macos": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    with_extra_toolchain(
        name = "%s/_doc_test_static_only" % name,
        extra_toolchain = ":%s/static_only_cc_toolchain" % name,
        target = "%s/__doc_test_with_dylib_dep" % name,
        tags = ["manual"],
        testonly = True,
    )
    rustdoc_link_args_analysis_test(
        name = "%s/doc_test_static_only" % name,
        target_under_test = "%s/_doc_test_static_only" % name,
        expected_any_of = ["-Clink-arg=-ldummy", "-Clink-arg=dummy"],
    )

    rust_static_library(
        name = "%s/__static_library" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        tags = ["manual", "nobuild"],
    )

    with_extra_toolchain(
        name = "%s/_static_library" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__static_library" % name,
        tags = ["manual"],
    )

    inputs_analysis_test(
        name = "%s/static_library" % name,
        target_under_test = "%s/_static_library" % name,
        expected_inputs = ["dummy.a"],
    )

    # A doc test links like a binary, so it needs the static runtime lib named
    # on the command line. `dummy.a` yields `dummy` via `get_lib_name`, spelled
    # `-ldummy` everywhere except msvc.
    rust_library(
        name = "%s/__doctest_library" % name,
        edition = "2018",
        srcs = ["lib.rs"],
        tags = ["manual", "nobuild"],
    )

    rust_doc_test(
        name = "%s/__doc_test" % name,
        crate = ":%s/__doctest_library" % name,
        tags = ["manual", "nobuild"],
    )

    with_extra_toolchain(
        name = "%s/_doc_test" % name,
        extra_toolchain = ":%s/test_cc_toolchain" % name,
        target = "%s/__doc_test" % name,
        tags = ["manual"],
        # rust_doc_test is a test rule, so it is testonly.
        testonly = True,
    )

    rustdoc_link_args_analysis_test(
        name = "%s/doc_test" % name,
        target_under_test = "%s/_doc_test" % name,
        expected_any_of = [
            "-Clink-arg=-ldummy",
            # msvc: link.exe takes bare library names, no `-l`.
            "-Clink-arg=dummy",
        ],
    )
