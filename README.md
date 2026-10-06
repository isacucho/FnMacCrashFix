# FnMacCrashFix

A lightweight macOS tweak aimed at mitigating Fortnite crash behavior and compatibility checks on Apple Silicon Macs. The project is built as a dynamic library and hooks selected system/runtime checks to reduce false positives, spoof device information, and bypass detection paths that would otherwise block or crash the app.

> This project is for research, experimentation, testing, and educational purposes only. It is not intended for general use or production deployment.

## Overview

This tweak focuses on patching several runtime checks used by Fortnite and similar apps, including:

- availability/version gate checks
- `sysctl` and `sysctlbyname` device queries
- process info detection such as `isiOSAppOnMac`, `isiOSAppOnMic`, and `isMacCatalystApp`
- dyld image enumeration and callback behavior for stealthier runtime hiding

The goal is to make the runtime look like a supported environment when the app performs compatibility and environment checks, while avoiding the crash-prone paths that are triggered on unsupported Mac execution.

## Build

From the project root:

```bash
make
```

This builds the dylib into the `build/` directory.

## Credits

- Original tweak: [xnetcat/FnMacCrashFix](https://github.com/xnetcat/FnMacCrashFix)
- Detection bypass work: [KohlerVG/FnMacTweak](https://github.com/kohlervg/fnmactweak)

Thanks to both projects for the original work and the detection bypass ideas that informed this implementation.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
