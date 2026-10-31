# Zelda3 WIREPROOF

A personal iOS and macOS adaptation of the open-source [zelda3 project](https://github.com/snesrev/zelda3), exploring A Link to the Past on Apple devices. The upstream README and licensing information are retained in this repository.

## iOS development build

The 0.2.2 build 4 IPA is an experimental arm64 build targeting iOS 15 or later on iPhone and iPad. It requires signing or a compatible sideloading environment. Its build record does not establish a physical-device gameplay test.

## Source and setup

Upstream game code is under `src/`; the Apple adaptation is under `platform/`, with build helpers in `scripts/`. Consult [upstream documentation](UPSTREAM-README.md) and the scripts for dependencies and game-data requirements. This snapshot excludes local saves, development environments, and build products. Original game assets and trademarks belong to their respective owners; this unofficial project is not affiliated with Nintendo.
