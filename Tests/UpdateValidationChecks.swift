import CryptoKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let validator = output.appendingPathComponent("validate-update")
let key = Curve25519.Signing.PrivateKey()
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
let feed = "https://openbar-update.invalid/appcast.xml"
let archive = output.appendingPathComponent("OpenBar-1.0.1-macos-arm64.zip")
let appcast = output.appendingPathComponent("appcast.xml")
let bytes = Data("Signed archive fixture".utf8)
let signature = try key.signature(for: bytes).base64EncodedString()
try bytes.write(to: archive)
let xml = """
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><title>OpenBar checks</title><item>
<sparkle:version>2</sparkle:version><sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="https://github.com/4nkitd/openbar/releases/download/v1.0.1/\(archive.lastPathComponent)" length="\(bytes.count)" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
</item></channel></rss>
"""
try xml.write(to: appcast, atomically: true, encoding: .utf8)

func run(_ arguments: [String], environment: [String: String], succeeds: Bool) throws {
    let process = Process()
    process.executableURL = validator
    process.arguments = arguments
    var values = ProcessInfo.processInfo.environment
    values.removeValue(forKey: "SPARKLE_FEED_URL")
    values.removeValue(forKey: "SPARKLE_PUBLIC_KEY")
    process.environment = values.merging(environment) { _, new in new }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard (process.terminationStatus == 0) == succeeds else {
        fatalError("Unexpected validation result for \(arguments): \(String(decoding: data, as: UTF8.self))")
    }
}

let environment = ["SPARKLE_FEED_URL": feed, "SPARKLE_PUBLIC_KEY": publicKey]
let validation = ["archive", "1.0.1", "2", archive.path, appcast.path]
try run(["configuration"], environment: [:], succeeds: true)
try run(["configuration"], environment: environment, succeeds: true)
try run(["configuration"], environment: ["SPARKLE_FEED_URL": feed], succeeds: false)
try run(["configuration"], environment: ["SPARKLE_FEED_URL": "http://example.test/feed", "SPARKLE_PUBLIC_KEY": publicKey], succeeds: false)
try run(["configuration"], environment: ["SPARKLE_FEED_URL": feed, "SPARKLE_PUBLIC_KEY": "invalid"], succeeds: false)
try run(["build", "3", appcast.path], environment: environment, succeeds: true)
try run(["build", "2", appcast.path], environment: environment, succeeds: false)
try run(["build", "1", appcast.path], environment: environment, succeeds: false)
try run(validation, environment: environment, succeeds: true)
let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
try run(validation, environment: ["SPARKLE_FEED_URL": feed, "SPARKLE_PUBLIC_KEY": otherKey], succeeds: false)
var tampered = bytes
tampered[0] ^= 1
try tampered.write(to: archive)
try run(validation, environment: environment, succeeds: false)
try bytes.write(to: archive)
try xml.replacingOccurrences(of: signature, with: "").write(to: appcast, atomically: true, encoding: .utf8)
try run(validation, environment: environment, succeeds: false)
try xml.write(to: appcast, atomically: true, encoding: .utf8)
try run(["archive", "1.0.2", "2", archive.path, appcast.path], environment: environment, succeeds: false)
let plist: [String: Any] = [
    "CFBundleExecutable": "SparkleChecks", "CFBundleIdentifier": "dev.openbar.sparkle-checks.\(UUID().uuidString)",
    "CFBundleName": "OpenBar checks", "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0.0", "LSUIElement": true,
    "SUFeedURL": feed, "SUPublicEDKey": publicKey, "SUEnableAutomaticChecks": false
]
let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try plistData.write(to: output.appendingPathComponent("SparkleChecks.app/Contents/Info.plist"))
print("PASS update configuration, increasing builds, signature/key match, archive tampering and version validation")
