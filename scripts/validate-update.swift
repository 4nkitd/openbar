import CryptoKit
import Foundation

struct ValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ValidationError(message: message) }
}

func publicKey() throws -> Curve25519.Signing.PublicKey? {
    let environment = ProcessInfo.processInfo.environment
    let feed = environment["SPARKLE_FEED_URL"] ?? ""
    let key = environment["SPARKLE_PUBLIC_KEY"] ?? ""
    if feed.isEmpty && key.isEmpty { return nil }
    guard let url = URL(string: feed), url.scheme == "https", url.host?.isEmpty == false,
          url.user == nil, url.password == nil, url.fragment == nil else {
        throw ValidationError(message: "SPARKLE_FEED_URL must be an HTTPS URL without credentials or a fragment.")
    }
    guard let bytes = Data(base64Encoded: key), bytes.count == 32 else {
        throw ValidationError(message: "SPARKLE_PUBLIC_KEY must be a base64-encoded 32-byte Ed25519 public key.")
    }
    return try Curve25519.Signing.PublicKey(rawRepresentation: bytes)
}

let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

func field(_ name: String, in element: XMLElement) throws -> String? {
    element.elements(forLocalName: name, uri: namespace).first?.stringValue
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let key = try publicKey()
    switch arguments.first {
    case "configuration":
        break
    case "build" where arguments.count == 3:
        guard let build = Int(arguments[1]), build > 0 else { throw ValidationError(message: "Build number must be a positive integer.") }
        let document = try XMLDocument(contentsOf: URL(fileURLWithPath: arguments[2]))
        for node in try document.nodes(forXPath: "/rss/channel/item") {
            guard let item = node as? XMLElement, let version = try field("version", in: item), let previous = Int(version) else {
                throw ValidationError(message: "Existing appcast contains an invalid build number.")
            }
            try require(build > previous, "Build \(build) must exceed existing appcast build \(previous).")
        }
    case "archive" where arguments.count == 5:
        guard let key else { throw ValidationError(message: "A feed and public key are required to validate a signed update.") }
        let version = arguments[1]
        let build = arguments[2]
        let archiveURL = URL(fileURLWithPath: arguments[3])
        let document = try XMLDocument(contentsOf: URL(fileURLWithPath: arguments[4]))
        let items = try document.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
        let matches = try items.filter { try field("version", in: $0) == build }
        try require(matches.count == 1, "Generated appcast must contain exactly one item for build \(build).")
        let item = matches[0]
        try require(try field("shortVersionString", in: item) == version, "Appcast version does not match the release.")
        guard let enclosure = item.elements(forName: "enclosure").first,
              let signature = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
              let signatureData = Data(base64Encoded: signature) else {
            throw ValidationError(message: "Generated update has no Ed25519 signature.")
        }
        let expectedURL = "https://github.com/4nkitd/openbar/releases/download/v\(version)/\(archiveURL.lastPathComponent)"
        try require(enclosure.attribute(forName: "url")?.stringValue == expectedURL, "Appcast download URL does not match the release archive.")
        let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        try require(enclosure.attribute(forName: "length")?.stringValue == String(archive.count), "Appcast archive size is incorrect.")
        try require(key.isValidSignature(signatureData, for: archive), "Update signature does not match SPARKLE_PUBLIC_KEY or the archive bytes.")
        print("Verified signed update \(version) (\(build)).")
    default:
        throw ValidationError(message: "Usage: swift validate-update.swift configuration | build <number> <appcast> | archive <version> <build> <zip> <appcast>")
    }
} catch {
    FileHandle.standardError.write(Data("Update validation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
