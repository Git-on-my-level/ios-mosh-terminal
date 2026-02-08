import Foundation

public enum OCBSessionError: Error, Equatable {
    case invalidKeyLength
    case contextAllocationFailed
    case initializationFailed
    case invalidCiphertext
    case encryptionFailed
    case decryptionFailed
    case authenticationFailed
}

@_silgen_name("ae_allocate")
private func ocb_ae_allocate(_ misc: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
@_silgen_name("ae_free")
private func ocb_ae_free(_ ctx: UnsafeMutableRawPointer?)
@_silgen_name("ae_clear")
private func ocb_ae_clear(_ ctx: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("ae_init")
private func ocb_ae_init(_ ctx: UnsafeMutableRawPointer?,
                         _ key: UnsafeRawPointer?,
                         _ keyLen: Int32,
                         _ nonceLen: Int32,
                         _ tagLen: Int32) -> Int32
@_silgen_name("ae_encrypt")
private func ocb_ae_encrypt(_ ctx: UnsafeMutableRawPointer?,
                            _ nonce: UnsafeRawPointer?,
                            _ pt: UnsafeRawPointer?,
                            _ ptLen: Int32,
                            _ ad: UnsafeRawPointer?,
                            _ adLen: Int32,
                            _ ct: UnsafeMutableRawPointer?,
                            _ tag: UnsafeMutableRawPointer?,
                            _ final: Int32) -> Int32
@_silgen_name("ae_decrypt")
private func ocb_ae_decrypt(_ ctx: UnsafeMutableRawPointer?,
                            _ nonce: UnsafeRawPointer?,
                            _ ct: UnsafeRawPointer?,
                            _ ctLen: Int32,
                            _ ad: UnsafeRawPointer?,
                            _ adLen: Int32,
                            _ pt: UnsafeMutableRawPointer?,
                            _ tag: UnsafeRawPointer?,
                            _ final: Int32) -> Int32

private enum OCBConstants {
    static let success: Int32 = 0
    static let invalid: Int32 = -1
    static let finalize: Int32 = 1
}

public final class OCBSession {
    private let ctx: UnsafeMutableRawPointer

    public init(key16: [UInt8]) throws {
        guard key16.count == 16 else {
            throw OCBSessionError.invalidKeyLength
        }
        guard let rawCtx = ocb_ae_allocate(nil) else {
            throw OCBSessionError.contextAllocationFailed
        }
        let initResult = key16.withUnsafeBytes { keyBytes in
            ocb_ae_init(rawCtx, keyBytes.baseAddress, Int32(key16.count), 12, 16)
        }
        guard initResult == OCBConstants.success else {
            ocb_ae_free(rawCtx)
            throw OCBSessionError.initializationFailed
        }
        ctx = rawCtx
    }

    deinit {
        _ = ocb_ae_clear(ctx)
        ocb_ae_free(ctx)
    }

    public func encrypt(nonceVal: UInt64, plaintext: Data) throws -> Data {
        let nonce12 = OCBSession.nonce12Bytes(for: nonceVal)
        let nonce8 = OCBSession.nonce8Bytes(for: nonceVal)
        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var tag = [UInt8](repeating: 0, count: 16)
        let plaintextBytes = [UInt8](plaintext)

        let result = nonce12.withUnsafeBytes { nonceBytes in
            plaintextBytes.withUnsafeBytes { ptBytes in
                ciphertext.withUnsafeMutableBytes { ctBytes in
                    tag.withUnsafeMutableBytes { tagBytes in
                        ocb_ae_encrypt(
                            ctx,
                            nonceBytes.baseAddress,
                            ptBytes.baseAddress,
                            Int32(plaintextBytes.count),
                            nil,
                            0,
                            ctBytes.baseAddress,
                            tagBytes.baseAddress,
                            OCBConstants.finalize
                        )
                    }
                }
            }
        }

        guard result >= 0, Int(result) == plaintextBytes.count else {
            throw OCBSessionError.encryptionFailed
        }

        var output = Data()
        output.append(contentsOf: nonce8)
        output.append(contentsOf: ciphertext)
        output.append(contentsOf: tag)
        return output
    }

    public func decrypt(ciphertext: Data) throws -> (nonceVal: UInt64, plaintext: Data) {
        guard ciphertext.count >= 24 else {
            throw OCBSessionError.invalidCiphertext
        }
        let nonce8 = [UInt8](ciphertext.prefix(8))
        let nonceVal = OCBSession.nonceVal(fromNonce8: nonce8)
        let nonce12 = OCBSession.nonce12Bytes(for: nonceVal)

        let payload = ciphertext.dropFirst(8)
        guard payload.count >= 16 else {
            throw OCBSessionError.invalidCiphertext
        }
        let ctBytes = [UInt8](payload.dropLast(16))
        let tagBytes = [UInt8](payload.suffix(16))
        var plaintext = [UInt8](repeating: 0, count: ctBytes.count)

        let result = nonce12.withUnsafeBytes { noncePtr in
            ctBytes.withUnsafeBytes { ctPtr in
                tagBytes.withUnsafeBytes { tagPtr in
                    plaintext.withUnsafeMutableBytes { ptPtr in
                        ocb_ae_decrypt(
                            ctx,
                            noncePtr.baseAddress,
                            ctPtr.baseAddress,
                            Int32(ctBytes.count),
                            nil,
                            0,
                            ptPtr.baseAddress,
                            tagPtr.baseAddress,
                            OCBConstants.finalize
                        )
                    }
                }
            }
        }

        if result == OCBConstants.invalid {
            throw OCBSessionError.authenticationFailed
        }
        guard result >= 0, Int(result) == ctBytes.count else {
            throw OCBSessionError.decryptionFailed
        }

        return (nonceVal, Data(plaintext))
    }

    private static func nonce8Bytes(for nonceVal: UInt64) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 8)
        var value = nonceVal
        for index in stride(from: 7, through: 0, by: -1) {
            bytes[index] = UInt8(truncatingIfNeeded: value)
            value >>= 8
        }
        return bytes
    }

    private static func nonce12Bytes(for nonceVal: UInt64) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 12)
        let nonce8 = nonce8Bytes(for: nonceVal)
        bytes.replaceSubrange(4..<12, with: nonce8)
        return bytes
    }

    private static func nonceVal(fromNonce8 nonce8: [UInt8]) -> UInt64 {
        var value: UInt64 = 0
        for byte in nonce8 {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}
