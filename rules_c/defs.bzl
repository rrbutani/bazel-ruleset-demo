
# load(":01_monolithic.bzl", "impl")
load(":03_reuse.bzl", "impl")

common_attributes = dict(
    sources = attr.label_list(
        doc = "`.c` files",
        allow_files = [".c"],
    ),
    headers = attr.label_list(
        doc = "`.h` files that are available to be included by reverse-deps",
        allow_files = [".h"],
    ),
    includes = attr.string_list(
        doc = (
            "package-relative directories to add to the include path for this "
            + "target as well as for reverse-deps "
            + "\n\n"
            + "paths provided cannot escape the current repository (with ../)"
            + "\n\n"
            + "by default only the current repository is added to the include "
            + "path (matches the `rules_cc` default)"
            + "\n\n"
            + "entries in this list must match at least one header in "
            + "`public_headers` and/or `private_headers`"
        ),
    ),
    dependencies = attr.label_list(
        doc = "other `c_library`s this target depends on",
        allow_files = False,
        providers = [impl.CInfo],
    ),
    private_headers = attr.label_list(
        doc = "`.h` files that are *not* available to reverse-deps",
        allow_files = [".h"],
    ), # doesn't really apply to `c_binary` (they're all private?) but whatever
)

c_library = rule(
    implementation = impl.c_library,
    attrs = common_attributes,
    executable = False,
    doc = "",
    provides = [impl.CInfo],
)

c_binary = rule(
    implementation = impl.c_binary,
    attrs = common_attributes,
    executable = True,
    doc = "",
    provides = [],
)
