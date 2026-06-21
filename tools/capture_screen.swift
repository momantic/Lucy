import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/lucy_linkedin_chrome_window.png"

guard let image = CGWindowListCreateImage(
    .infinite,
    .optionOnScreenOnly,
    kCGNullWindowID,
    [.bestResolution]
) else {
    fputs("Swift screen capture failed\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: out) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Could not create image destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) {
    fputs("Could not write image\n", stderr)
    exit(1)
}
print(out)
