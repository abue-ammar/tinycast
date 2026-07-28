import CryptoKit
import Foundation

/// Minimal scrypt (RFC 7914) key-derivation, vendored so the Raycast import needs no third-party crypto dependency. PBKDF2-HMAC-SHA256 rides on CryptoKit; the Salsa20/8 core, BlockMix and ROMix are the standard reference construction. Run it off the main actor — it's CPU-heavy by design.
enum Scrypt {
    /// Derive `dkLen` key bytes. For Raycast: `n=16384, r=8, p=1, dkLen=32`.
    static func derive(
        passphrase: [UInt8], salt: [UInt8], n: Int, r: Int, p: Int, dkLen: Int
    ) -> [UInt8] {
        let blockLen = 128 * r
        var b = pbkdf2(password: passphrase, salt: salt, rounds: 1, dkLen: p * blockLen)
        for i in 0..<p {
            var block = Array(b[i * blockLen..<(i + 1) * blockLen])
            romix(&block, n: n, r: r)
            b.replaceSubrange(i * blockLen..<(i + 1) * blockLen, with: block)
        }
        return pbkdf2(password: passphrase, salt: b, rounds: 1, dkLen: dkLen)
    }

    // MARK: - PBKDF2-HMAC-SHA256

    private static func pbkdf2(
        password: [UInt8], salt: [UInt8], rounds: Int, dkLen: Int
    ) -> [UInt8] {
        let hLen = 32
        let key = SymmetricKey(data: password)
        let blocks = (dkLen + hLen - 1) / hLen
        var derived = [UInt8]()
        derived.reserveCapacity(blocks * hLen)
        for i in 1...blocks {
            let intBE: [UInt8] = [
                UInt8((i >> 24) & 0xff), UInt8((i >> 16) & 0xff),
                UInt8((i >> 8) & 0xff), UInt8(i & 0xff),
            ]
            var u = hmac(key: key, data: salt + intBE)
            var t = u
            if rounds > 1 {
                for _ in 1..<rounds {
                    u = hmac(key: key, data: u)
                    for k in 0..<hLen { t[k] ^= u[k] }
                }
            }
            derived.append(contentsOf: t)
        }
        return Array(derived.prefix(dkLen))
    }

    private static func hmac(key: SymmetricKey, data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    // MARK: - ROMix / BlockMix / Salsa20/8

    private static func romix(_ b: inout [UInt8], n: Int, r: Int) {
        let blockLen = 128 * r
        var x = b
        var v = [UInt8](repeating: 0, count: n * blockLen)
        for i in 0..<n {
            v.replaceSubrange(i * blockLen..<(i + 1) * blockLen, with: x)
            x = blockMix(x, r: r)
        }
        for _ in 0..<n {
            let j = integerify(x, r: r) % n
            for k in 0..<blockLen { x[k] ^= v[j * blockLen + k] }
            x = blockMix(x, r: r)
        }
        b = x
    }

    /// `B` is `2r` 64-byte blocks → `Y[0],Y[2],…,Y[2r-2],Y[1],Y[3],…,Y[2r-1]`.
    private static func blockMix(_ input: [UInt8], r: Int) -> [UInt8] {
        var x = Array(input[(2 * r - 1) * 64..<2 * r * 64])
        var out = [UInt8](repeating: 0, count: 128 * r)
        for i in 0..<(2 * r) {
            for k in 0..<64 { x[k] ^= input[i * 64 + k] }
            x = salsa20_8(x)
            let dest = (i % 2 == 0) ? i / 2 : r + i / 2
            for k in 0..<64 { out[dest * 64 + k] = x[k] }
        }
        return out
    }

    /// Little-endian 32-bit word at the start of the last 64-byte block, mod N.
    private static func integerify(_ x: [UInt8], r: Int) -> Int {
        let o = (2 * r - 1) * 64
        return Int(
            UInt32(x[o]) | UInt32(x[o + 1]) << 8 | UInt32(x[o + 2]) << 16 | UInt32(x[o + 3]) << 24)
    }

    private static func salsa20_8(_ input: [UInt8]) -> [UInt8] {
        var x = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let o = i * 4
            x[i] =
                UInt32(input[o]) | UInt32(input[o + 1]) << 8 | UInt32(input[o + 2]) << 16
                | UInt32(input[o + 3]) << 24
        }
        let orig = x

        @inline(__always) func rotl(_ a: UInt32, _ b: UInt32) -> UInt32 {
            (a << b) | (a >> (32 - b))
        }

        var i = 8
        while i > 0 {
            x[4] ^= rotl(x[0] &+ x[12], 7)
            x[8] ^= rotl(x[4] &+ x[0], 9)
            x[12] ^= rotl(x[8] &+ x[4], 13)
            x[0] ^= rotl(x[12] &+ x[8], 18)
            x[9] ^= rotl(x[5] &+ x[1], 7)
            x[13] ^= rotl(x[9] &+ x[5], 9)
            x[1] ^= rotl(x[13] &+ x[9], 13)
            x[5] ^= rotl(x[1] &+ x[13], 18)
            x[14] ^= rotl(x[10] &+ x[6], 7)
            x[2] ^= rotl(x[14] &+ x[10], 9)
            x[6] ^= rotl(x[2] &+ x[14], 13)
            x[10] ^= rotl(x[6] &+ x[2], 18)
            x[3] ^= rotl(x[15] &+ x[11], 7)
            x[7] ^= rotl(x[3] &+ x[15], 9)
            x[11] ^= rotl(x[7] &+ x[3], 13)
            x[15] ^= rotl(x[11] &+ x[7], 18)
            x[1] ^= rotl(x[0] &+ x[3], 7)
            x[2] ^= rotl(x[1] &+ x[0], 9)
            x[3] ^= rotl(x[2] &+ x[1], 13)
            x[0] ^= rotl(x[3] &+ x[2], 18)
            x[6] ^= rotl(x[5] &+ x[4], 7)
            x[7] ^= rotl(x[6] &+ x[5], 9)
            x[4] ^= rotl(x[7] &+ x[6], 13)
            x[5] ^= rotl(x[4] &+ x[7], 18)
            x[11] ^= rotl(x[10] &+ x[9], 7)
            x[8] ^= rotl(x[11] &+ x[10], 9)
            x[9] ^= rotl(x[8] &+ x[11], 13)
            x[10] ^= rotl(x[9] &+ x[8], 18)
            x[12] ^= rotl(x[15] &+ x[14], 7)
            x[13] ^= rotl(x[12] &+ x[15], 9)
            x[14] ^= rotl(x[13] &+ x[12], 13)
            x[15] ^= rotl(x[14] &+ x[13], 18)
            i -= 2
        }

        var out = [UInt8](repeating: 0, count: 64)
        for k in 0..<16 {
            let v = x[k] &+ orig[k]
            let o = k * 4
            out[o] = UInt8(v & 0xff)
            out[o + 1] = UInt8((v >> 8) & 0xff)
            out[o + 2] = UInt8((v >> 16) & 0xff)
            out[o + 3] = UInt8((v >> 24) & 0xff)
        }
        return out
    }
}
