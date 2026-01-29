import Foundation

public struct HiPrintPacketizer {
    public init() {}

    public static func makeHeader(payloadLength: Int) -> Data {
        precondition(payloadLength >= 0 && payloadLength <= 0xFFFFFF, "Payload length must fit in 3 bytes")
        var header = Data(capacity: 10)
        header.append(UInt8((payloadLength >> 16) & 0xFF))
        header.append(UInt8((payloadLength >> 8) & 0xFF))
        header.append(UInt8(payloadLength & 0xFF))
        header.append(contentsOf: HiPrintConstants.headerTail)
        return header
    }

    public static func packetize(payload: Data, maxDataBytes: Int = 200) -> [Data] {
        precondition(maxDataBytes > 0 && maxDataBytes <= 200, "maxDataBytes should be 1..200")
        let header = makeHeader(payloadLength: payload.count)
        var packets: [Data] = [header]

        var offset = 0
        while offset < payload.count {
            let chunkLen = min(maxDataBytes, payload.count - offset)
            var frame = Data(capacity: 5 + chunkLen)
            frame.append(UInt8((offset >> 16) & 0xFF))
            frame.append(UInt8((offset >> 8) & 0xFF))
            frame.append(UInt8(offset & 0xFF))
            frame.append(0x00) // flags
            frame.append(UInt8(chunkLen))
            frame.append(payload.subdata(in: offset..<(offset + chunkLen)))
            packets.append(frame)
            offset += chunkLen
        }
        return packets
    }
}
