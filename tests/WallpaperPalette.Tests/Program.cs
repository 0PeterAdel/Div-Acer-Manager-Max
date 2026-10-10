using System.Diagnostics;
using DivAcerManagerMax;
using SkiaSharp;

void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
    Console.WriteLine("PASS: " + message);
}

var red = new SKColor(255, 0, 0);
var blue = new SKColor(0, 0, 255);
var green = new SKColor(0, 255, 0);
var pixels = Enumerable.Repeat(red, 750).Concat(Enumerable.Repeat(blue, 200))
    .Concat(Enumerable.Repeat(green, 50)).ToArray();
var ranked = WallpaperPalette.ExtractColors(pixels, 6);
Check(ranked.Count == 3 && ranked[0].Hex == "FF0000" && Math.Abs(ranked[0].Coverage - 0.75) < 0.001,
    "Most frequent color ranks first with correct image coverage");
Check(ranked.Select(c => c.Hex).SequenceEqual(WallpaperPalette.ExtractColors(pixels.Reverse(), 6).Select(c => c.Hex)),
    "Pixel order does not change the palette");
var shades = WallpaperPalette.ExtractColors(Enumerable.Repeat(red, 500)
    .Concat(Enumerable.Repeat(new SKColor(240, 8, 4), 400)).Concat(Enumerable.Repeat(blue, 100)), 6);
Check(shades.Count == 2 && shades[0].Red >= 240 && shades[0].Coverage > 0.89,
    "Nearby shades combine without hiding distinct accent colors");
Check(WallpaperPalette.ExtractColors(Enumerable.Repeat(red, 999).Append(green), 6).Count == 1,
    "Isolated pixel noise is not offered as a prominent color");
var transparent = WallpaperPalette.ExtractColors(Enumerable.Repeat(new SKColor(255, 0, 0, 0), 900)
    .Concat(Enumerable.Repeat(green, 100)), 6);
Check(transparent.Count == 1 && transparent[0].Hex == "00FF00" && transparent[0].Coverage == 1,
    "Invisible pixels do not dominate the palette");
Check(WallpaperPalette.ExtractColors(Enumerable.Repeat(SKColors.Black, 100), 6).Single().Hex == "000000",
    "Monochrome images still produce a valid choice");
try
{
    WallpaperPalette.ExtractColors(new[] { SKColors.Transparent }, 6);
    throw new Exception("All-transparent image was accepted");
}
catch (InvalidDataException) { Console.WriteLine("PASS: Empty visible palette is reported"); }

var directory = Path.Combine(Path.GetTempPath(), "damx-palette-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(directory);
try
{
    var imagePath = Path.Combine(directory, "sample.png");
    using (var bitmap = new SKBitmap(100, 100))
    {
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(red);
        using var paint = new SKPaint { Color = blue };
        canvas.DrawRect(75, 0, 25, 100, paint);
        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(SKEncodedImageFormat.Png, 100);
        using var file = File.Create(imagePath);
        encoded.SaveTo(file);
    }
    var decoded = WallpaperPalette.Extract(imagePath);
    Check(decoded.Count == 2 && decoded[0].Hex == "FF0000" && decoded[0].Coverage == 0.75,
        "Real PNG decoding preserves dominant color and coverage");
    var current = Path.Combine(directory, "state", "omarchy", "current");
    Directory.CreateDirectory(current);
    File.CreateSymbolicLink(Path.Combine(current, "background"), imagePath);
    Check(WallpaperPalette.FindOmarchyWallpaper(Path.Combine(directory, "state"), Path.Combine(directory, "config")) == imagePath,
        "Current Omarchy wallpaper symlink resolves to the image");
    File.Delete(Path.Combine(current, "background"));
    Check(WallpaperPalette.FindOmarchyWallpaper(Path.Combine(directory, "state"), Path.Combine(directory, "config")) == null,
        "Missing wallpaper allows the manual image fallback");
    File.WriteAllText(Path.Combine(directory, "invalid.jpg"), "not an image");
    try
    {
        WallpaperPalette.Extract(Path.Combine(directory, "invalid.jpg"));
        throw new Exception("Invalid image was accepted");
    }
    catch (InvalidDataException) { Console.WriteLine("PASS: Invalid image is reported"); }
}
finally { Directory.Delete(directory, true); }

var wallpaper = WallpaperPalette.FindCurrentWallpaper();
if (wallpaper != null)
{
    var timer = Stopwatch.StartNew();
    var palette = WallpaperPalette.Extract(wallpaper);
    Check(palette.Count is >= 1 and <= 6, "Current desktop wallpaper extracts successfully");
    Console.WriteLine($"Wallpaper: {Path.GetFileName(wallpaper)} ({timer.ElapsedMilliseconds} ms)");
    foreach (var color in palette) Console.WriteLine($"  #{color.Hex}: {color.Coverage:P1}");
}
