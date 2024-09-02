# AppsEngine
App isolated server with swift.

## Environment variable `RUNTIME_VERBOSE`
`,` separated words
* `metric`: enable verbose of `Metric`.
* `logging`: output log from `LoggingSystem`.
* `error_caller`: capture caller with stack trace, may cause crash on Linux.
* `route`: print register route while app started.
