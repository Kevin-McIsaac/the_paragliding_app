---
title: Flutter 3.47 Impeller is slow on Linux without a GPU
created: '2026-11-09T03:00:00Z'
updated: '2026-11-09T03:00:00Z'
uuid: 79a9bac1-def4-4956-b83a-957f1b333f50
summary: Flutter 3.47+ defaults to Impeller on Linux desktop; on this GPU-less Crostini VM it is about 2x slower than Skia, and screenshots stop working.
---

Flutter **3.47.0** is the first stable that defaults to **Impeller** on Linux desktop.
The change is `dcae056e7ef` in `flutter_tools` (2026-06-03): `desktop_device.dart`
stopped passing `--enable-impeller=false` for `platformDefault`. The last stable that
forces Skia on Linux is **3.44.9** (2026-08-05).

This Crostini container has **no `/dev/dri`** and no virtio-gpu (`dmesg` shows none),
so Impeller rasterises on the CPU (llvmpipe). Measured 2026-11-09 on Flutter 3.47.9:

- first screen 6.2 s vs 2.5-2.7 s with Skia;
- interactions about 2x slower (statistics 325-460 ms vs 188-250 ms; a Holfuy tap
  3.3 s vs 1.4 s);
- `_flutter.screenshot` fails with "Compressed screenshots not supported for Impeller",
  so `bin/dev_screenshot.sh` and `bin/dev_input.sh` are unusable.

Workaround: `flutter run --no-enable-impeller` (hidden flag) still selects Skia in 3.47.
`bin/dev_run.sh` now adds it for Linux desktop automatically; `DEV_RUN_IMPELLER=1`
opts back in, and an explicit `--enable-impeller` wins.

Caveat: a packaged Linux release started outside `flutter run` still uses the engine
default. Android is unaffected because the device has a GPU.

Sources: local Flutter SDK git history, `desktop_device.dart` at 3.41.6/3.44.9/3.47.9,
and the app's `dev_data/flutter.log` from the 2026-11-09 runs.
