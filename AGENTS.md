# Agent instructions

This repository is the Ada 2022 `sitefetch` command-line crate.

## Toolchain

Use Alire GNAT 15 only. Do not run plain system `gnat*`, `gnatmake`, `gnatls`,
`gnatprove`, or `gprbuild` in this workspace. Use `alr exec -- ...` for
compiler, prover, and builder commands so PATH cannot select a different GNAT
installation.

The development, release, and tests manifests must pin:

```toml
[[depends-on]]
gnat_native = "=15.2.1"
```

Confirm the selected compiler with:

```sh
alr exec -- gnatls --version
```

## Validation

Preferred validation:

```sh
alr build
./bin/check_sitefetch
cd tests && alr build && ./bin/tests
```

When GNAT/GPRBuild/GNATprove are unavailable through Alire, state that clearly
and run the static checks the environment supports.

## Boundaries

`sitefetch` is the CLI layer over sibling `../sitefetchlib`. Use
`project_tools` for repository tooling and release checks only; do not add
system GNAT/GPR toolchain dependencies.
