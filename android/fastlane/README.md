fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android build

```sh
[bundle exec] fastlane android build
```

Build the release AAB with Flutter

### android internal

```sh
[bundle exec] fastlane android internal
```

Upload the already-built release AAB to the Play internal track

### android build_internal

```sh
[bundle exec] fastlane android build_internal
```

Build then upload to the Play internal track

### android production

```sh
[bundle exec] fastlane android production
```

Promote the current build to production (staged rollout starts in Play Console)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
