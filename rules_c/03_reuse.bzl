
load(":headers.bzl", "headers")

load("@bazel_skylib//lib:paths.bzl", "paths")

CInfo = provider(
    doc = "C source code information",
    fields = dict(
        obj_files = "depset[File]",
        headers = "depset[File]",
        includes = "depset[HeaderIncludePathInfo]",
    ),
)

def _compile_source_files(
    ctx, source_files, header_files, includes,
    extra_flags = [], extension = ".o",
):
    compiler = ctx.configuration.default_shell_env.get("CC", "clang")
    include_args = (
        headers
            .add_include_args(ctx.actions.args(), includes)
            .use_param_file("@%s")
    )

    obj_files = []
    for source in source_files:
        # TODO: make guaranteed unique names?
        obj_file_path = paths.join(
            "_{}_objs".format(ctx.label.name),
            source.owner.repo_name,
            source.short_path,
        )
        obj_file_path = paths.replace_extension(obj_file_path, extension)
        obj_file = ctx.actions.declare_file(obj_file_path)

        args = (
            ctx.actions.args()
                .add("-c")
                .add("-o", obj_file)
                # .add("-x", "c")
                .add("-fcolor-diagnostics")
                .add(source)
                .add_all(extra_flags)
        )
        ctx.actions.run(
            executable = compiler,
            outputs = [obj_file],
            inputs = depset([source], transitive = [header_files]),
            arguments = [args, include_args],
            mnemonic = "CCompile",
            progress_message = (
                "Compiling {name} (%{label})".replace("{name}", source.basename)
            ),
            use_default_shell_env = True,
            execution_requirements = { "supports-path-mapping": "true" }
        )

        obj_files.append(obj_file)

    return obj_files

# https://bazel.build/rules/lib/builtins/depset.html
def _collect_transitive_info(ctx, **kwargs):
    deps = ctx.attr.dependencies

    direct_source_files = ctx.files.sources
    private_header_files = depset(ctx.files.private_headers)
    public_header_files = depset(
        ctx.files.headers,
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

    # flatten into pub/priv depsets:
    mk_inc_path_infos = lambda idx: [
        path_info
        # pair has `tuple[pub, priv]`
        for pair in custom_includes_inc_path_infos + [repo_root_inc_path_infos]
        for path_info in pair[idx]
    ]
    direct_pub_inc_path_infos = mk_inc_path_infos(0)
    direct_priv_inc_path_infos = mk_inc_path_infos(1)

    pub_inc_path_infos = depset(
        direct_pub_inc_path_infos,
        transitive = [ dep[CInfo].includes for dep in deps ],
        order = "topological",
    )
    priv_inc_path_infos = depset(
        direct_priv_inc_path_infos,
        order = "topological",
    )

    # construct `.o` files
    direct_obj_files = _compile_source_files(
        ctx,
        direct_source_files,
        # direct private and direct + transitive public headers/includes:
        depset(transitive = [private_header_files, public_header_files]),
        depset(transitive = [priv_inc_path_infos, pub_inc_path_infos]),
        **kwargs,
    )
    obj_files = depset(
        direct_obj_files,
        transitive = [ dep[CInfo].obj_files for dep in deps ],
        order = "topological",
    )

    return direct_obj_files, CInfo(
        obj_files = obj_files,
        headers = public_header_files,
        includes = pub_inc_path_infos,
    )


def c_library(ctx):
    direct_obj_files, c_info = _collect_transitive_info(
        ctx, extra_flags = ["-fpic"], extension = ".pic.o",
    )
    return [DefaultInfo(files = depset(direct_obj_files)), c_info]

def c_binary(ctx):
    _, c_info = _collect_transitive_info(
        ctx, extra_flags = ["-fpie"], extension = ".pie.o",
    )

    # TODO: should use `--start-lib`, `--end-lib`; don't want to unconditionally
    # link in everything!
    #  - requires that we track groups of object files
    binary = ctx.actions.declare_file(ctx.label.name)
    compiler = ctx.configuration.default_shell_env.get("CC", "clang")
    ctx.actions.run(
        executable = compiler,
        outputs = [binary],
        inputs = depset(transitive = [c_info.obj_files]),
        arguments = [(
            ctx.actions.args()
                .add("-o", binary)
                .add("-fcolor-diagnostics")
                .add("-Wl,--gc-sections")
                .add_all(c_info.obj_files)
                .use_param_file("@%s")
        )],
        mnemonic = "CLink",
        progress_message = (
            "Linking {name} (%{label})".replace("{name}", ctx.label.name)
        ),
        use_default_shell_env = True,
        execution_requirements = { "supports-path-mapping": "true" }
        # TODO: `resource_set`; memory requirement scale with # of obj files...
    )

    return [DefaultInfo(executable = binary)]

impl = struct(
    CInfo = CInfo,
    c_library = c_library,
    c_binary = c_binary,
)
