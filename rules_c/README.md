
> [!CAUTION]
> We're purposefully eliding tons of detail and nuance here! Including, but not limited to:
>  - modeling tools with a toolchain
>  - hermeticity considerations (i.e. modeling system headers)
>  - distinguishing between system and user headers
>  - reproducibility considerations: `-march=native`, `-frandom-seed`, `-fdebug-prefix`, `-no-canonical-prefixes`, `-ffile-reproducible`
>  - modeling cross-compilation
>  - handling of `copts`, `defines`, linker scripts, and other functionality
>  - thinLTO
>  - optimization levels
>  - debug symbol related features (fission, stripping)
>  - advanced header include path manipulation (`include_prefix`, `strip_include_prefix`)
>  - makevar substitution
>  - data deps, runfiles support
>  - stamping support
>  - shared object output support
>  - link mode configuration (i.e. static vs. dynamic)
>  - C++20 module support, PCH support
>  - C++ support
>  - interop with other native-code producing rulesets (i.e. `rules_rust`, `CcInfo`-producers)
>  - test support, code coverage
>  - profiling, PGO, FDO
>  - instrumentation (interposers, custom malloc)
>  - sanitizer support
>  - codegen options for: frame-pointers, pic/pie
>  - warnings, lints, error-reporting machinery
>  - ... and much more
>
> Do **not** actually attempt to model C/C++ compilation this way; use `rules_cc` instead.

---

We're implementing this interface:

```python
c_library(
    name = "",
    sources = [],         # `.c` files
    headers = [],         # `.h` files
    includes = [],        # package-relative directories to add to the include
                          # path for this target as well as reverse-deps
    dependencies = [],    # other `c_library` targets
    private_headers = [], # `.h` files, *not* available to reverse-deps
)

c_binary(
    name = "",
    sources = [],      # `.c` files
    headers = [],      # `.h` files
    includes = [],     # package-relative directories to add to the include path
    dependencies = [], # `c_library` targets
)
```

todo:
  - graph with multiple c_binary targets
    + json guy as a library, export types in headers, use in downstream

impls:
  1. simple
      + one command line invocation for everything
      * [ ] show: note that `-I` only includes the necessary files due to sandbox symlink trees
      * [ ] show: missing header, doesn't work
      * [ ] show: glob in action (`print` statement too)
      * [ ] note: what happens if you have multiple headers with the same name?
  2. granular
      + have top-level `c_binary` do multiple invocations
      + upside is better incremental builds, more parallelism for better wall-clock times
  3. actions follow graph structure
      + have each `c_library` do work, propagate artifacts upwards
        * explain `DefaultInfo`
      + upside is even more reuse
  4. public headers vs. private headers: enforcement
      + show missing dep in graph, etc.
  5. taking it even further: `-E` expansion
      + `-E` expansion step to root out non-consequential changes (i.e. header that's not included)
        * note: not always worth it; expanded contents may be Big
  6. taking it _even_ further: IFSO
      + what if: silently shared objects? (interface shared objects)
        * trade a little runtime performance for lower build times
        * ECO so that we only have to recompile rdeps on interface changes, not implementation changes
      + all things we can do without changing the interface

todo:
  - show json trace of what ran for each guy

other things to point out:
  - contract is "file" — can replace with a genrule
    + [ ] show example of this
  - contract is `CInfo` — can replace with other things that provide a `CInfo` (i.e. parser generator like `flex`/`bison`)
    + in reality the abstraction is even more generic — `CcInfo` is anything that produces native code (i.e. `rust_library`)
  - we are making a granularity tradeoff:
    + i.e. `c_library` _is_ a coarsening of the graph
    + max granularity would mean spelling out exactly what `.h` files each `.c` file uses
      * this would be incredibly cumbersome for the user
    + instead we "coarsen" by grouping files into `c_library`s and spell out dependency relationships at that level instead
    + we then:
      * use the `-E` normalization approach (or really, in practice, `.d` files) to recover performance — i.e. to remove over-declared deps

even further stuff:
  7. guard against "unused" headers with `iwyu`
  8. guard against unused Bazel target dependencies
  9. `header_parse` feature
  10. guarding against inclusion of untracked headers

---

aspects:
  - you can actually go further; don't even need to modify the rule, can impl each of ^ atop existing graphs of rules using `aspect`s

---

exercises in graph propagation:
  - propagate up the graph?
    * i.e. a `define`
  - propagate down the graph?
    * (you should probably never do this)
    * i.e. say you need to build some code with `-Og` for some reason
    * options:
      + configuration + transition (best)
      + aspect (ehhhh)
