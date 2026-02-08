import Foundation
import zlib

public enum ZlibCodecError: Error, Equatable {
    case compressionFailed(code: Int32)
    case decompressionFailed(code: Int32)
    case outputTooLarge(max: Int)
    case invalidLimit
}

public enum ZlibCodec {
    public static let defaultMaxOutputBytes = 4 * 1024 * 1024

    public static func compress(_ data: Data) throws -> Data {
        let sourceCount = data.count
        let bound = zlib.compressBound(uLong(sourceCount))
        var destination = Data(count: Int(bound))
        var destinationLength = uLongf(bound)

        let status = destination.withUnsafeMutableBytes { destinationBytes -> Int32 in
            return data.withUnsafeBytes { sourceBytes -> Int32 in
                let sourcePointer = sourceBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
                let destinationPointer = destinationBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
                return zlib.compress(destinationPointer, &destinationLength, sourcePointer, uLong(sourceCount))
            }
        }

        guard status == Z_OK else {
            throw ZlibCodecError.compressionFailed(code: status)
        }

        destination.count = Int(destinationLength)
        return destination
    }

    public static func decompress(_ data: Data, maxOutputBytes: Int = defaultMaxOutputBytes) throws -> Data {
        guard maxOutputBytes >= 0 else {
            throw ZlibCodecError.invalidLimit
        }

        var stream = z_stream()
        let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw ZlibCodecError.decompressionFailed(code: initStatus)
        }
        defer {
            inflateEnd(&stream)
        }

        let chunkSize = 32 * 1024
        var output = Data()
        output.reserveCapacity(min(maxOutputBytes, chunkSize))

        return try data.withUnsafeBytes { sourceBytes -> Data in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: sourceBytes.baseAddress?.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(sourceBytes.count)

            var status: Int32 = Z_OK
            while true {
                if output.count >= maxOutputBytes {
                    throw ZlibCodecError.outputTooLarge(max: maxOutputBytes)
                }

                let remaining = maxOutputBytes - output.count
                let outputChunkSize = min(chunkSize, remaining)
                var outputChunk = [UInt8](repeating: 0, count: outputChunkSize)
                let produced = outputChunk.withUnsafeMutableBytes { outputBytes -> Int in
                    stream.next_out = outputBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(outputChunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return outputChunkSize - Int(stream.avail_out)
                }
                if produced > 0 {
                    output.append(outputChunk, count: produced)
                }

                switch status {
                case Z_STREAM_END:
                    return output
                case Z_OK:
                    continue
                default:
                    throw ZlibCodecError.decompressionFailed(code: status)
                }
            }
        }
    }
}
