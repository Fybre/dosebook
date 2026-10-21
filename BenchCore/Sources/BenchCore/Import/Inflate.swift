import Foundation
import Compression

/// DEFLATE decoding through Apple's Compression framework, which reads raw
/// DEFLATE: what a zip entry holds, and a zlib stream once its header is skipped.
enum Inflate {
    /// A raw DEFLATE stream.
    static func raw(_ input: [UInt8]) -> [UInt8]? {
        guard !input.isEmpty else { return [] }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }
        let chunk = 64 * 1024
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { outBuf.deallocate() }
        var out: [UInt8] = []
        return input.withUnsafeBufferPointer { inBuf -> [UInt8]? in
            stream.pointee.src_ptr = inBuf.baseAddress!
            stream.pointee.src_size = inBuf.count
            while true {
                stream.pointee.dst_ptr = outBuf
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                out.append(contentsOf: UnsafeBufferPointer(start: outBuf, count: chunk - stream.pointee.dst_size))
                switch status {
                case COMPRESSION_STATUS_END: return out
                case COMPRESSION_STATUS_OK:
                    // No progress and nothing left to read: a truncated stream.
                    if stream.pointee.src_size == 0 && stream.pointee.dst_size == chunk { return out.isEmpty ? nil : out }
                default: return nil
                }
            }
        }
    }

    /// A zlib stream (RFC 1950): a two-byte header, DEFLATE, then a checksum.
    static func zlib(_ input: [UInt8]) -> [UInt8]? {
        guard input.count >= 2, input[0] & 0x0F == 8, (UInt16(input[0]) << 8 | UInt16(input[1])) % 31 == 0 else { return nil }
        return raw(Array(input.dropFirst(2)))
    }
}

/// Just enough of the zip format to open an .xlsx: the central directory,
/// stored and deflated entries. No zip64, no encryption.
enum Zip {
    struct Failure: Error {}

    static func entries(_ bytes: [UInt8]) throws -> [String: [UInt8]] {
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 22 else { throw Failure() }
        // End of central directory, searched backwards past any trailing comment.
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 22 - 65_535) {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure() }
        let count = u16(eocd + 10)
        var at = u32(eocd + 16)
        var out: [String: [UInt8]] = [:]
        for _ in 0..<count {
            guard at + 46 <= bytes.count, u32(at) == 0x0201_4b50 else { throw Failure() }
            let method = u16(at + 10), compressed = u32(at + 20), nameLen = u16(at + 28)
            let extraLen = u16(at + 30), commentLen = u16(at + 32), local = u32(at + 42)
            guard at + 46 + nameLen <= bytes.count else { throw Failure() }
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLen)], as: UTF8.self)
            guard local + 30 <= bytes.count, u32(local) == 0x0403_4b50 else { throw Failure() }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count else { throw Failure() }
            let body = Array(bytes[start..<(start + compressed)])
            switch method {
            case 0: out[name] = body
            case 8: guard let d = Inflate.raw(body) else { throw Failure() }; out[name] = d
            default: break
            }
            at += 46 + nameLen + extraLen + commentLen
        }
        return out
    }
}
