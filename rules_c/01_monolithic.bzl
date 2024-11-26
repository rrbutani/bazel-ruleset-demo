"""
propagate everything up, compile in one go in `c_binary`

cons:
    - granularity -> caching
    - granularity -> parallelism
    - granularity -> can't reuse work amongst multiple `c_binary` targets
    - can't enforce layering
    - can't build `c_library` targets to check that stuff works
"""

load(":headers.bzl", "headers")

CInfo = provider(
    doc = "C source code information",
    fields = dict(
        sources = "depset[File]",
        headers = "depset[File]",
        includes = "depset[HeaderIncludePathInfo]",
    ),
)

# See: https://bazel.build/rules/lib/builtins/depset.html
def _collect_transitive_info(ctx):
    deps = ctx.attr.dependencies

    source_files = depset(
        ctx.files.sources,
        transitive = [ dep[CInfo].sources for dep in deps ],
        order = "postorder",
    )
    header_files = depset(
        ctx.files.headers + ctx.files.private_headers,
        transitive = [ dep[CInfo].headers for dep in deps ],
    )

    repo_root_inc_path_infos = headers.for_repo_relative_include(
        ctx, ctx.files.headers, ctx.files.private_headers, ".",
    )
    custom_includes_inc_path_infos = [
        headers.for_pkg_relative_include(
            ctx, ctx.files.headers, ctx.files.private_headers,
            rel_inc_dir,
        )
        for rel_inc_dir in ctx.attr.includes
    ]

    # flatten into one depset:
    direct_inc_path_infos = [
        path_info
        # pair has `tuple[pub, priv]`; we're not making a distinction for now
        for pair in custom_includes_inc_path_infos + [repo_root_inc_path_infos]
        for path_infos in pair
        for path_info in path_infos
    ]
    inc_path_infos = depset(
        direct_inc_path_infos,
        transitive = [ dep[CInfo].includes for dep in deps ],
        order = "topological",
    )

    return CInfo(
        sources = source_files,
        headers = header_files,
        includes = inc_path_infos,
    )


def c_library(ctx):
    return [_collect_transitive_info(ctx)]

def c_binary(ctx):
    c_info = _collect_transitive_info(ctx)

    binary = ctx.actions.declare_file(ctx.label.name)
    compiler = ctx.configuration.default_shell_env.get("CC", "clang")
    args = (
        ctx.actions.args()
            .add("-o", binary)
            # .add("-x", "c")
            .add("-fcolor-diagnostics")
            .add_all(c_info.sources)
            .use_param_file("@%s")
    )
    args = headers.add_include_args(args, c_info.includes)
    ctx.actions.run(
        executable = compiler,
        outputs = [binary],
        inputs = depset(transitive = [c_info.sources, c_info.headers]),
        arguments = [args],
        mnemonic = "CCompile",
        progress_message = (
            "Compiling {name} (%{label})".replace("{name}", ctx.label.name)
        ),
        use_default_shell_env = True,
        execution_requirements = { "supports-path-mapping": "true" }
    )

    return [DefaultInfo(executable = binary)]

impl = struct(
    CInfo = CInfo,
    c_library = c_library,
    c_binary = c_binary,
)
