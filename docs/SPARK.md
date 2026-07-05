# SPARK Coverage

`sitefetch` runs GNATprove as part of release validation:

```sh
alr exec -- gnatprove -P sitefetch.gpr --level=0 --mode=check
```

The deterministic command-line parser entry point `Sitefetch.CLI.Parse` is SPARK-enabled. Its body-level parsing helpers for option prefix checks, natural-number conversion, cache/head/limit option selection, and positional argument handling are also annotated with `SPARK_Mode => On`. `Sitefetch.CLI.Parse_Command_Line` remains ordinary Ada because it reads the current process arguments through `Ada.Command_Line` and then delegates to the deterministic parser.

Pure app formatting helpers have been moved out of `Sitefetch.App` into `Sitefetch.App_Format`, which is SPARK-enabled. This package owns JSON escaping/string/boolean formatting, natural-number rendering, and stable progress event names used by JSON progress and summaries.

The remaining `Sitefetch.App` orchestration is intentionally outside SPARK for now. It combines terminal I/O, localized message lookup, filesystem checks, wall-clock timing, callback dispatch, and the production crawler boundary. Those effects are release-tested through the CLI tests and sibling crate release checks rather than proved directly.
