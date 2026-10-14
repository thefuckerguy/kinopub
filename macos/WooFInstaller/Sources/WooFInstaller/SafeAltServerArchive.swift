import Foundation
import zlib

/// Checks ZIP metadata and actual decoded sizes/CRCs before extraction. ZIP64/encryption are rejected.
enum SafeAltServerArchive {
    private struct Entry {
        let path: String
        let symlink: Bool
    }

    static func validate(_ data: Data) throws {
        guard data.count >= 22, data.count <= 128 * 1_048_576 else { throw AltServerError.invalidArchive }
        func number(_ offset: Int, _ width: Int) throws -> Int {
            guard offset >= 0, width <= data.count, offset <= data.count - width else { throw AltServerError.invalidArchive }
            return (0..<width).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        var end: Int?
        for index in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try number(index, 4) == 0x06054b50,
               index + 22 + (try number(index + 20, 2)) == data.count { end = index; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw AltServerError.invalidArchive }
        let count = try number(end + 10, 2)
        let centralSize = try number(end + 12, 4)
        var cursor = try number(end + 16, 4)
        let centralStart = cursor
        guard count > 0, count < 10_000, try number(end + 8, 2) == count,
              cursor + centralSize == end else { throw AltServerError.invalidArchive }
        var entries: [Entry] = []
        var expanded = 0
        var names = Set<String>()
        var records: [Range<Int>] = []
        func validateExtra(_ start: Int, _ length: Int) throws {
            guard start + length <= data.count else { throw AltServerError.invalidArchive }
            var position = start
            while position < start + length {
                guard position + 4 <= start + length else { throw AltServerError.invalidArchive }
                let tag = try number(position, 2)
                let fieldLength = try number(position + 2, 2)
                // Disallow ZIP64 and Unicode filename overrides interpreted differently by extractors.
                guard tag != 0x0001, tag != 0x7075,
                      position + 4 + fieldLength <= start + length else { throw AltServerError.invalidArchive }
                position += 4 + fieldLength
            }
        }
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014b50 else { throw AltServerError.invalidArchive }
            let flags = try number(cursor + 8, 2)
            let method = try number(cursor + 10, 2)
            let checksum = try number(cursor + 16, 4)
            let compressedSize = try number(cursor + 20, 4)
            let size = try number(cursor + 24, 4)
            let nameLength = try number(cursor + 28, 2)
            let extraLength = try number(cursor + 30, 2)
            let commentLength = try number(cursor + 32, 2)
            let mode = try number(cursor + 38, 4) >> 16
            let local = try number(cursor + 42, 4)
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard flags & ~0x080E == 0, method == 0 || method == 8,
                  try number(cursor + 34, 2) == 0, next <= end,
                  local < cursor, try number(local, 4) == 0x04034b50,
                  try number(local + 6, 2) == flags, try number(local + 8, 2) == method,
                  try number(local + 26, 2) == nameLength else { throw AltServerError.invalidArchive }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let localNameEnd = local + 30 + nameLength
            guard localNameEnd <= data.count,
                  data.subdata(in: (local + 30)..<localNameEnd) == nameData,
                  let raw = String(data: nameData, encoding: .utf8) else { throw AltServerError.invalidArchive }
            let path = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            try validatePath(path)
            guard names.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw AltServerError.invalidArchive }
            let fileType = mode & 0o170000
            guard fileType == 0 || fileType == 0o100000 || fileType == 0o040000 || fileType == 0o120000 else {
                throw AltServerError.invalidArchive
            }
            let payload = localNameEnd + (try number(local + 28, 2))
            try validateExtra(cursor + 46 + nameLength, extraLength)
            try validateExtra(localNameEnd, number(local + 28, 2))
            guard payload + compressedSize <= centralStart else { throw AltServerError.invalidArchive }
            let localChecksum = try number(local + 14, 4)
            let localCompressedSize = try number(local + 18, 4)
            let localSize = try number(local + 22, 4)
            var recordEnd = payload + compressedSize
            if flags & 8 != 0 {
                // Streaming ZIPs put authoritative metadata in a descriptor after the payload.
                guard (localChecksum == 0 || localChecksum == checksum),
                      (localCompressedSize == 0 || localCompressedSize == compressedSize),
                      (localSize == 0 || localSize == size) else { throw AltServerError.invalidArchive }
                if try number(recordEnd, 4) == 0x08074b50 { recordEnd += 4 }
                guard recordEnd + 12 <= centralStart,
                      try number(recordEnd, 4) == checksum,
                      try number(recordEnd + 4, 4) == compressedSize,
                      try number(recordEnd + 8, 4) == size else { throw AltServerError.invalidArchive }
                recordEnd += 12
            } else {
                guard localChecksum == checksum, localCompressedSize == compressedSize,
                      localSize == size else { throw AltServerError.invalidArchive }
            }
            records.append(local..<recordEnd)
            let symlink = fileType == 0o120000
            if symlink {
                // Official framework links are stored, relative forward paths (Versions/Current/...).
                guard path.hasPrefix("AltServer.app/"), method == 0, size == compressedSize, size < 4096,
                      let target = String(data: data.subdata(in: payload..<(payload + size)), encoding: .utf8) else {
                    throw AltServerError.invalidArchive
                }
                try validateComponents(target)
            }
            expanded += size
            guard expanded <= 512 * 1_048_576 else { throw AltServerError.invalidArchive }
            try validatePayload(data, range: payload..<(payload + compressedSize), method: method,
                                expectedSize: size, expectedCRC: UInt32(checksum))
            entries.append(Entry(path: path, symlink: symlink))
            cursor = next
        }
        guard cursor == end, entries.contains(where: { $0.path == "AltServer.app/Contents/Info.plist" }) else {
            throw AltServerError.invalidArchive
        }
        // tar reads local records: every byte before the directory must belong to a checked member.
        var expectedOffset = 0
        for record in records.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard record.lowerBound == expectedOffset else { throw AltServerError.invalidArchive }
            expectedOffset = record.upperBound
        }
        guard expectedOffset == centralStart else { throw AltServerError.invalidArchive }
        // No archive member may be written through a symlink, regardless of extraction order.
        for link in entries where link.symlink {
            guard !entries.contains(where: { $0.path.lowercased().hasPrefix(link.path.lowercased() + "/") }) else {
                throw AltServerError.invalidArchive
            }
        }
    }

    private static func validatePayload(_ data: Data, range: Range<Int>, method: Int,
                                        expectedSize: Int, expectedCRC: UInt32) throws {
        try data.withUnsafeBytes { raw in
            let input = raw.bindMemory(to: Bytef.self).baseAddress!.advanced(by: range.lowerBound)
            if method == 0 {
                guard range.count == expectedSize,
                      UInt32(crc32(0, input, uInt(range.count))) == expectedCRC else { throw AltServerError.invalidArchive }
                return
            }
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw AltServerError.invalidArchive
            }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer(mutating: input)
            stream.avail_in = uInt(range.count)
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var decoded = 0
            var checksum: uLong = 0
            while true {
                let (status, produced) = buffer.withUnsafeMutableBytes { output -> (Int32, Int) in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(output.count)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    let produced = output.count - Int(stream.avail_out)
                    checksum = crc32(checksum, stream.next_out!.advanced(by: -produced), uInt(produced))
                    return (status, produced)
                }
                decoded += produced
                // Reject a lying size as soon as it exceeds its claim, without writing any files.
                guard decoded <= expectedSize else { throw AltServerError.invalidArchive }
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0, decoded == expectedSize,
                          UInt32(checksum) == expectedCRC else { throw AltServerError.invalidArchive }
                    return
                }
                guard status == Z_OK, produced > 0 else { throw AltServerError.invalidArchive }
            }
        }
    }

    private static func validatePath(_ path: String) throws {
        try validateComponents(path)
        guard path == "AltServer.app" || path.hasPrefix("AltServer.app/")
                || path == "__MACOSX" || path.hasPrefix("__MACOSX/") else { throw AltServerError.invalidArchive }
    }

    private static func validateComponents(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw AltServerError.invalidArchive }
    }
}
