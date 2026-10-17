# Vendored dependencies

All dependency source needed by the build and tests is included as ordinary files. No package download, submodule, install step, or external library linking is required. Files are unmodified from the pinned release archives.

## openzeppelin-contracts v5.2.0

Source: [v5.2.0](https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.2.0)

Archive SHA-256: `80f86d2dba4e1c0d66a216d2ddf0ac5d731edf9338ea12a985edca8774802814`

Only ERC20 and its transitive imports, plus the MIT license, are vendored.

## forge-std v1.9.7

Source: [v1.9.7](https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7)

Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

The `src/` tree and both upstream licenses (MIT and Apache-2.0) are vendored for tests.

Per-file SHA-256 hashes are recorded in `dependencies.sha256`; check with `sha256sum --check dependencies.sha256`.
