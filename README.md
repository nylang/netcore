# net_core

Independent Nyra networking foundation. This repository currently provides a
package scaffold and implementation roadmap, not a working network client.

The compiler and package manager will consume its public APIs. Networking does
not belong in the language frontend or CodeGen. Implementation dependencies
will use the public kernel/stdlib APIs; OS socket and event adapters stay private.
No libcurl dependency or compiler-specific API is part of this package.

See [ROADMAP.md](ROADMAP.md).

## License

Licensed under the [MIT License](LICENSE).
