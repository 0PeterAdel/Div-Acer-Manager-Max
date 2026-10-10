# Wallpaper lighting colors

The Wallpaper Colors card in Keyboard Lighting extracts prominent colors from
an image and offers them as Static lighting choices. It shows the source image,
RGB values and approximate image coverage. Select a swatch, choose Keyboard,
Back Logo / Lightbar, or both, then press Apply Static Color.

The palette loads automatically when DAMX opens. Use Current Wallpaper reads
the current Omarchy wallpaper, supporting both its state-directory and older
configuration-directory symlinks, including custom XDG paths. Choose Image
provides a local image picker when the desktop's wallpaper path is unavailable
or when the user wants colors from another image.

Extracting colors and selecting a swatch do not write to the lighting hardware.
Apply uses the existing Static keyboard and logo APIs. The current brightness
is preserved, as is the logo's enabled/disabled setting. Keyboard selection is
saved with the existing effect and zone presets. Targets are shown only when
their driver capabilities are available.

Processing runs off the UI thread. The extractor samples at up to 192 pixels
on the longest side, groups similar shades, ranks them by image coverage and
removes duplicate shades and tiny color artifacts. Transparent pixels are
excluded. It returns up to six colors and also handles monochrome images.
Unsupported images, missing files and images exceeding the decoding limits
produce an explanatory status without changing the lighting.

Run the headless extraction tests with:

```bash
dotnet run --project tests/WallpaperPalette.Tests -c Release
```

The customized `reinstall-damx.sh` builds this feature along with all other GUI,
daemon and driver source changes; it requires no extra desktop configuration.
