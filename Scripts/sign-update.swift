#!/usr/bin/env swift
// Sign an updater zip with the key the app itself trusts. Usage: sign-update.swift <app> <zip>
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else { fail("usage: sign-update.swift <app> <zip>") }
let app = URL(fileURLWithPath: arguments[0])
let zip = URL(fileURLWithPath: arguments[1])

guard let encoded = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"],
    let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
    let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else { fail("UPDATE_SIGNING_KEY is missing or is not a base64 Ed25519 private key") }

let info = NSDictionary(contentsOf: app.appending(components: "Contents", "Info.plist"))
let trusted = info?["TinycastUpdatePublicKey"] as? String
guard trusted == key.publicKey.rawRepresentation.base64EncodedString() else {
    fail("\(app.lastPathComponent) trusts another update key and could never install the next release")
}

guard let data = try? Data(contentsOf: zip) else { fail("cannot read \(zip.path)") }
let signature = try key.signature(for: data).base64EncodedString()
try Data(signature.utf8).write(to: zip.appendingPathExtension("sig"))
print("✓ signed \(zip.lastPathComponent)")
