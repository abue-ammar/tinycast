import CloudKit
import Foundation

/// One record type for every item, so a new kind of data never changes Config/CloudKit/schema.ckdb.
enum CloudSyncRecordCodec {
    static let recordType = "SyncItem"
    /// Raised only when an older build could misread a payload; it then pauses rather than guess.
    static let schemaVersion = 1
    static let zoneID = CKRecordZone.ID(zoneName: "Tinycast")

    /// CloudKit caps a record at 1 MB, so anything near it travels as an asset instead.
    private static let assetThreshold = 512 * 1024

    struct Item {
        let source: SyncSourceID
        let key: String
        let payload: Data
        let modifiedAt: Date
        let schemaVersion: Int
    }

    private enum Field {
        static let key = "key"
        static let payload = "payload"
        static let payloadAsset = "payloadAsset"
        static let modifiedAt = "modifiedAt"
        static let schemaVersion = "schemaVersion"
    }

    static func recordID(named name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// Built on the server's last known copy, which is what lets a save land without a conflict.
    static func record(
        named name: String, systemFields: Data?, key: String, payload: Data, modifiedAt: Date,
        assetDirectory: URL
    ) throws -> CKRecord {
        let record =
            systemFields.flatMap(decodeSystemFields)
            ?? CKRecord(recordType: recordType, recordID: recordID(named: name))
        record.encryptedValues[Field.key] = key
        record[Field.modifiedAt] = modifiedAt
        record[Field.schemaVersion] = schemaVersion
        if payload.count > assetThreshold {
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
            let url = assetDirectory.appending(path: name)
            try payload.write(to: url, options: [.atomic])
            record[Field.payloadAsset] = CKAsset(fileURL: url)
            record.encryptedValues[Field.payload] = nil
        } else {
            record.encryptedValues[Field.payload] = payload
            record[Field.payloadAsset] = nil
        }
        return record
    }

    /// Nil for a record this build can't read: a foreign type, a newer source or a missing key.
    static func item(from record: CKRecord) -> Item? {
        guard
            record.recordType == recordType,
            let source = SyncSourceID(recordName: record.recordID.recordName),
            let key = record.encryptedValues[Field.key] as? String,
            let payload = payload(of: record)
        else { return nil }
        return Item(
            source: source, key: key, payload: payload,
            modifiedAt: record[Field.modifiedAt] as? Date ?? .distantPast,
            schemaVersion: record[Field.schemaVersion] as? Int ?? 0)
    }

    static func schemaVersion(of record: CKRecord) -> Int {
        record[Field.schemaVersion] as? Int ?? 0
    }

    static func modifiedAt(of record: CKRecord) -> Date {
        record[Field.modifiedAt] as? Date ?? .distantPast
    }

    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    private static func payload(of record: CKRecord) -> Data? {
        if let payload = record.encryptedValues[Field.payload] as? Data { return payload }
        guard let url = (record[Field.payloadAsset] as? CKAsset)?.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
