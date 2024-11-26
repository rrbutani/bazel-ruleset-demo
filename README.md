previously: https://gist.github.com/rrbutani/e23d68acef3f300dd87b3a8190832c72
  - example going over some basics:
    + macros, `genrule`, rules, BUILD files, `rules_python`

want to cover:
  - [ ] basics: label, target, packages, BUILD files, repos, etc.
  - [ ] genrule
  - [ ] phases: loading, analysis, execution
    + query
    + phase ordering restriction
  - [ ] macros + load-time stuff
    + `.bzl` files; show expansion
    + show off that these can be involved
    + misc convenience stuff like: glob
  - [ ] rules
    + interface: attributes
    + actions: APIs, what they represent, aquery
    + providers: communicating stuff up the graph
  - [ ] demonstration: rule interface is decoupled from actions (execution)
    + actions are lazy
    + show: monolith, granular with same rule interface
  - [ ] design principles for rulesets
    + explicit deps; hierarchically described
    + composability: providers
    + strict interfaces: providers and "artifacts"; encapsulate internal details
      * i.e. don't make assumptions about directory structure
      * more work for ruleset authors to get tools to conform to this ideal but
      * results in a higher level of abstraction
        - better user experience, more leverage for ruleset authors
      * example: include dirs for C/C++, python path
    + high-level: abstract away domain-specific details where possible
      * i.e. include paths, object files, command line flags
      * optimize for the common case, but: provide escape hatches where necessary
    + generally prefer smaller pieces of work (more granularity)
      * optimize for reuse
      * take advantage of ECO (i.e. by normalizing in places)
    + encapsulation: hide implementation specific details
      * i.e. file paths, private headers and files, incidental details about directory layout
    + ensure the dep graph as Bazel sees it matches reality
      * requires extra effort
      * i.e. artifact of include paths and transitive includes (C preprocessor) is that targets can implicitly depend on headers from transitive deps (aka checking for "layering violations")
        - not a correctness issue but is still undesirable:
          + does an end-run around Bazel's visibility machinery
          + static graph is less accurate: can't find all the genuine direct rdeps

this time: using C compilation as our example since it's something we're all familiar with
