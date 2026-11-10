# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Attributes for selecting the C++ toolchain runtime on Rust links."""

CC_RUNTIME_LINKAGE_ATTRS = {
    "cc_runtime_linkage": attr.string(
        doc = """Selects the C++ toolchain runtime libraries supplied to this link.

- `auto` (default): follow the effective Rust standard-library linkage selected
  by `link_std_dylib` or the toolchain's `experimental_link_std_dylib` setting.
  Prefer the dynamic runtime for dynamic Rust std, otherwise the static runtime.
  If the toolchain supplies only a static runtime, auto falls back to it.
- `static`: select the toolchain's static runtime libraries.
- `dynamic`: select the toolchain's dynamic runtime libraries. Fail if the
  toolchain supplies only a static runtime instead of silently changing linkage.

This selects the toolchain runtime, not ordinary native dependency linkage.
Toolchains that supply no runtime libraries remain supported. It does not
control runtimes already linked into dependencies or guarantee that only one
runtime is loaded in the process. Use `select()` to vary the policy by platform.
""",
        values = ["auto", "dynamic", "static"],
        default = "auto",
    ),
}
