import Foundation
import CommonCrypto
import CryptoKit
import Security

enum XiaomiCrypto {
    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    static func hmacSHA256(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    static func hexToBytes(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
        guard clean.count == 32, clean.count % 2 == 0 else { return nil }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    /// miwear-auth: HMAC-SHA256 based KDF used by the watch-face auth handshake.
    static func kdfMiwear(secret: Data, phoneNonce: Data, watchNonce: Data) -> Data {
        var initKey = Data()
        initKey.append(phoneNonce)
        initKey.append(watchNonce)
        let hmacKey = hmacSHA256(key: initKey, data: secret)
        var output = Data()
        var previous = Data()
        for counter in UInt8(1)...3 {
            var input = Data()
            input.append(previous)
            input.append(Data("miwear-auth".utf8))
            input.append(counter)
            previous = hmacSHA256(key: hmacKey, data: input)
            output.append(previous)
        }
        return Data(output.prefix(64))
    }

    static func aesCTR(key: Data, iv: Data, data: Data) -> Data {
        guard key.count == 16, iv.count == 16 else { return data }
        var counter = [UInt8](iv)
        var output = [UInt8]()
        output.reserveCapacity(data.count)
        var offset = 0
        let input = [UInt8](data)
        while offset < input.count {
            let stream = aesBlock(key: key, block: Data(counter))
            let streamBytes = [UInt8](stream)
            let count = min(16, input.count - offset)
            for i in 0..<count {
                output.append(input[offset + i] ^ streamBytes[i])
            }
            offset += count
            incrementCounter(&counter)
        }
        return Data(output)
    }

    static func aesBlock(key: Data, block: Data) -> Data {
        var output = Data(count: kCCBlockSizeAES128)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outBytes -> CCCryptorStatus in
            block.withUnsafeBytes { blockBytes -> CCCryptorStatus in
                key.withUnsafeBytes { keyBytes -> CCCryptorStatus in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        blockBytes.baseAddress,
                        kCCBlockSizeAES128,
                        outBytes.baseAddress,
                        kCCBlockSizeAES128,
                        &moved
                    )
                }
            }
        }
        return status == kCCSuccess ? output : Data(repeating: 0, count: 16)
    }

    private static func incrementCounter(_ counter: inout [UInt8]) {
        for index in stride(from: counter.count - 1, through: 0, by: -1) {
            if counter[index] == 0xFF {
                counter[index] = 0
            } else {
                counter[index] += 1
                break
            }
        }
    }

    /// AES-128-CCM with a 12-byte nonce and 4-byte tag, matching the
    /// `ccm` crate configuration used by the Xiaomi protocol.
    static func aesCCMEncrypt(key: Data, nonce: Data, aad: Data, plaintext: Data, tagLength: Int = 4) -> Data {
        guard key.count == 16, nonce.count == 12 else { return Data() }
        let tag = ccmTag(key: key, nonce: nonce, aad: aad, plaintext: plaintext, tagLength: tagLength)
        let L = 15 - nonce.count
        var a0 = Data([UInt8(L - 1)])
        a0.append(nonce)
        a0.append(Data(repeating: 0, count: L))
        let s0 = aesBlock(key: key, block: a0)
        var ciphertext = aesCTRCCM(key: key, nonce: nonce, data: plaintext)
        ciphertext.append(xor(tag, Data(s0.prefix(tagLength))))
        return ciphertext
    }

    static func aesCCMDecrypt(key: Data, nonce: Data, aad: Data, ciphertext: Data, tagLength: Int = 4) -> Data? {
        guard ciphertext.count >= tagLength else { return nil }
        let body = Data(ciphertext.prefix(ciphertext.count - tagLength))
        let expectedTag = Data(ciphertext.suffix(tagLength))
        let plain = aesCTRCCM(key: key, nonce: nonce, data: body)
        let tag = ccmTag(key: key, nonce: nonce, aad: aad, plaintext: plain, tagLength: tagLength)
        guard tag == expectedTag else { return nil }
        return plain
    }

    private static func ccmTag(key: Data, nonce: Data, aad: Data, plaintext: Data, tagLength: Int) -> Data {
        let L = 15 - nonce.count
        let flags = UInt8((aad.isEmpty ? 0 : 0x40) | (((tagLength - 2) / 2) << 3) | (L - 1))
        var b0 = Data([flags])
        b0.append(nonce)
        b0.append(lengthBytes(plaintext.count, length: L))

        var x = aesBlock(key: key, block: b0)

        if !aad.isEmpty {
            var aadBlock = Data()
            aadBlock.append(UInt8((aad.count >> 8) & 0xFF))
            aadBlock.append(UInt8(aad.count & 0xFF))
            aadBlock.append(aad)
            while aadBlock.count % 16 != 0 { aadBlock.append(0) }
            for block in stride(from: 0, to: aadBlock.count, by: 16) {
                let chunk = aadBlock.subdata(in: block..<(block + 16))
                x = aesBlock(key: key, block: xor(x, chunk))
            }
        }

        if !plaintext.isEmpty {
            var padded = plaintext
            while padded.count % 16 != 0 { padded.append(0) }
            for block in stride(from: 0, to: padded.count, by: 16) {
                let chunk = padded.subdata(in: block..<(block + 16))
                x = aesBlock(key: key, block: xor(x, chunk))
            }
        }
        return Data(x.prefix(tagLength))
    }

    /// CCM's counter mode shares the same keystream structure as the CTR
    /// helper, but starts at counter 1 and uses an L-byte counter.
    private static func aesCTRCCM(key: Data, nonce: Data, data: Data) -> Data {
        let L = 15 - nonce.count
        var output = Data()
        var counter: UInt32 = 1
        var offset = 0
        let input = [UInt8](data)
        while offset < input.count {
            var ai = Data([UInt8(L - 1)])
            ai.append(nonce)
            ai.append(counterBytes(counter, length: L))
            let stream = [UInt8](aesBlock(key: key, block: ai))
            let count = min(16, input.count - offset)
            for i in 0..<count { output.append(input[offset + i] ^ stream[i]) }
            offset += count
            counter &+= 1
        }
        return output
    }

    private static func xor(_ lhs: Data, _ rhs: Data) -> Data {
        let count = min(lhs.count, rhs.count)
        var result = Data(count: count)
        for i in 0..<count { result[i] = lhs[i] ^ rhs[i] }
        return result
    }

    private static func lengthBytes(_ value: Int, length: Int) -> Data {
        var result = Data(repeating: 0, count: length)
        var v = value
        for index in stride(from: length - 1, through: 0, by: -1) {
            result[index] = UInt8(v & 0xFF)
            v >>= 8
        }
        return result
    }

    private static func counterBytes(_ value: UInt32, length: Int) -> Data {
        var result = Data(repeating: 0, count: length)
        var v = value
        for index in stride(from: length - 1, through: 0, by: -1) {
            result[index] = UInt8(v & 0xFF)
            v >>= 8
        }
        return result
    }
}

struct XiaomiL2Cipher {
    let encryptionKey: Data
    let decryptionKey: Data

    func encrypt(_ plaintext: Data) -> Data {
        XiaomiCrypto.aesCTR(key: encryptionKey, iv: encryptionKey, data: plaintext)
    }

    func decrypt(_ ciphertext: Data) -> Data {
        XiaomiCrypto.aesCTR(key: decryptionKey, iv: decryptionKey, data: ciphertext)
    }
}
