
# We're cutting lots of corners here!
#
# NOTE: _should_ account for `sibling_repository_layout` to handle "external"
# (i.e. files in other repos) correctly but we're not doing this for simplicity
#
# NOTE: should attempt to handle header files that live in a different
# repository than the target in a better way — i.e. probably include that repo's
# root in the include path...
#
# NOTE: we _should_ probably construct virtual include directories (tree
# artifacts)? not sure what the interaction with path-mapping is...
#   - the real motivation is to keep includes from accidentally making other
#     headers that are transitively pulled in available via paths they're not
#     intended to be visible at
#
# NOTE: this implementation is particularly inefficient; we could/should eagerly
# dedupe entries that ultimately point to the same directory...

load("@bazel_skylib//lib:paths.bzl", "paths")

def _mk_header_include_path_info(header, strip_suffix):
    if type(header) != "File": fail(type(header), "not a File")
    if not header.path.endswith(strip_suffix): fail(header.path, strip_suffix)
    remaining = header.path.removesuffix(strip_suffix)
    if not remaining.endswith("/") or remaining == "": fail(
        "not aligned; removing", strip_suffix, "from", header.path, "yields",
        remaining
    )

    return dict(header = header, strip_suffix = strip_suffix)
_, HeaderIncludePathInfo = provider(
    doc = (
        "A header file and path suffix path; corresponds to a single `-I` flag."
        + "\n\n"
        + "Note that we do not eagerly (before action execution) strip the "
        + "suffixes from `header.path` and only propagate the resulting string "
        + "due to path-mapping: the runtime execpath of `header` may not match "
        + "`header.path`."
    ),
    fields = dict(
        header = "File",
        strip_suffix = "string",
    ),
    init = _mk_header_include_path_info,
)

def get_header_include_path_infos(
    ctx,
    public_headers, # list[File]
    private_headers, # list[File]
    repo_relative_include_path = ".", # relative path as a string
): # -> tuple[[HeaderIncludePathInfo], [HeaderIncludePathInfo]]
    repo = ctx.label.repo_name

    repo_relative_include_path = paths.normalize(repo_relative_include_path)
    if repo_relative_include_path.startswith(".."): fail(
        "repo-relative path must not escape repo", repo_relative_include_path,
    )

    def _process_list(headers):
        out = []
        for h in headers:
            # Ignore any files that don't live in the same repo as the target:
            if h.owner and h.owner.repo_name != repo: continue

            # `h.path` returns: `<root>/<repo dir>/<repo_relative_path>`
            #
            # `<root>` may vary from file to file, even for files within the
            # same repo as it is influenced by whether a file is generated, the
            # compilation mode, and potentially the configuration used to build
            # `h`.
            #
            # `<repo dir>` should be consistent for a particular repo but it's
            # hard to compute statically; it depends on whether `repo` is the
            # main repo and whether the sibling external repository layout is
            # enabled.
            #
            # See:
            #  - https://bazel.build/rules/lib/builtins/File#path
            #  - https://bazel.build/rules/lib/builtins/root.html
            #
            # For the purposes of checking whether `h` matches
            # `repo_relative_include_path` we only want to consider the
            # `repo_relative_path` porition (i.e. not `root` and `repo dir`).
            #
            # Note that `join(h.owner.package, h.owner.name)` is unfortunately
            # not equivalent to this — the "owner" Label needn't correspond
            # directly to the `File` that we have (consider a target that
            # produces many files).

            # Here's what `root.path`, `short_path`, and `path` look like for
            # the matrix of `src/gen`, `main/ext`, sibling layout/not options:
            #
            # | Src? | Repo | Sibling |                       Path                            | Runfiles Path (short_path)  |
            # |:----:|:----:|:-------:|:-----------------------------------------------------:|:---------------------------:|
            # |  Src | Main |    no   | <pkg path>/<name>                                     | <pkg path>/<name>           |
            # |  Gen | Main |    no   | <root in bazel-out>/<pkg path>/<name>                 | <pkg path>/<name>           |
            # |  Src |  Ext |    no   | external/<repo>/<pkg path>/<name>                     | ../<repo>/<pkg path>/<name> |
            # |  Gen |  Ext |    no   | <root in bazel-out>/external/<repo>/<pkg path>/<name> | ../<repo>/<pkg path>/<name> |
            # |  Src | Main |   yes   | --- (same)                                            | --- (same)                  |
            # |  Gen | Main |   yes   | --- (same)                                            | --- (same)                  |
            # |  Src |  Ext |   yes   | ../<repo>/<pkg path>/<name> (same as runfiles)        | --- (same)                  |
            # |  Gen |  Ext |   yes   | bazel-out/<repo>/<cfg>/<pkg path>/<name>              | --- (same)                  |
            #                           \--------------------/
            #                                 `root.path`
            #
            # Using the above, we divine `repo_relative_path`:
            repo_relative_path = None
            if h.owner.repo_name == "": # main repo
                repo_relative_path = h.short_path
            else: # external repo
                root_external_and_repo = paths.join(
                    h.root.path, "external", h.owner.repo_name,
                )
                uplevel_repo = "../" + h.owner.repo_name
                if h.path.startswith(root_external_and_repo): # no sibling path
                    repo_relative_path = paths.relativize(
                        h.path, root_external_and_repo,
                    )
                elif h.path.startswith(uplevel_repo): # sibling layout, src file
                    repo_relative_path = paths.relativize(
                        h.path, uplevel_repo,
                    )
                elif h.path.startswith(h.root.path) and h.root.path != "":
                    # assert that `root.path` is `bazel-*/<repo>`
                    r = h.root.path.split("/")
                    if r[0].startswith("bazel-") and r[1] == h.owner.repo_name:
                        repo_relative_path = paths.relativize(
                            h.path, h.root.path,
                        )
                    else: fail()
                else: fail(h, h.path, h.short_path, h.root.path)

            '''
            if any([ h.path.endswith(x) for x in ["recog_centaur.h", "extra_header.h", "a.h", "gen.h"] ]):
                print(h.path)
                print(h.short_path)
                print(h.root.path)
                print(repo_relative_path)
                print("----")
                # print()
            '''

            if (
                repo_relative_include_path == "." or paths.starts_with(
                    repo_relative_path, repo_relative_include_path
                )
            ):
                # Guard against `includes` that point at header files, not dirs:
                if repo_relative_path == repo_relative_include_path: fail(
                    "repo-relative path must be a directory, not a file",
                    repo_relative_include_path, "matches", h,
                )
                out.append(HeaderIncludePathInfo(
                    header = h,
                    strip_suffix = paths.relativize(
                        repo_relative_path,
                        repo_relative_include_path,
                    ),
                ))
        return out

    return _process_list(public_headers), _process_list(private_headers)

def get_header_include_path_infos_for_pkg_rel_inc(
    ctx, public_headers, private_headers, package_relative_include,
):
    repo_relative_include_path = paths.join(
        ctx.label.package,
        package_relative_include,
    )
    pub, priv = get_header_include_path_infos(
        ctx, public_headers, private_headers, repo_relative_include_path,
    )

    if not pub and not priv: fail(
        "package-relative include path", package_relative_include,
        "matched no private or public headers",
    )
    return pub, priv

# See: https://github.com/bazelbuild/bazel/discussions/22658
def _compute_include_arg(inc_path_info, _dir_expander):
    dir = inc_path_info.header.path.removesuffix(inc_path_info.strip_suffix)
    return dir or "."

def add_include_args(args, include_path_infos, arg = "-I"):
    args.add_all(
        include_path_infos,
        before_each = arg,
        map_each = _compute_include_arg,
        uniquify = True,
    )
    return args

headers = struct(
    for_repo_relative_include = get_header_include_path_infos,
    for_pkg_relative_include = get_header_include_path_infos_for_pkg_rel_inc,
    add_include_args = add_include_args,
)

# for now: error on files not in the main repo? idk
