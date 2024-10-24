//
//  CloudKitExchange.swift
//  Forked
//
//  Created by Drew McCormack on 14/08/2024.
//
import CloudKit
import SwiftUI
import Forked
import os.log

extension Logger {
    static let exchange = Logger(subsystem: "forked", category: "CloudKitExchange")
}

extension Fork {
    static let cloudKitUpload: Self = .init(name: "cloudKitUpload")
    static let cloudKitDownload: Self = .init(name: "cloudKitDownload")
}

extension CKRecord {
    static let resourceDataKey = "resourceData"
}

@available(iOS 17.0, tvOS 17.0, watchOS 10.0, macOS 14.0, *)
public final class CloudKitExchange<R: Repository>: @unchecked Sendable where R.Resource: Codable {
    let id: String
    let forkedResource: ForkedResource<R>
    let cloudKitContainer: CKContainer
    let zoneID: CKRecordZone.ID = .init(zoneName: "Forked")
    let recordType: CKRecord.RecordType = "ForkedResource"
    var recordID: CKRecord.ID { CKRecord.ID(recordName: id, zoneID: zoneID) }
    
    internal private(set) var engine: CKSyncEngine!
    
    private let dataURL: URL
    
    private struct SyncState: Codable {
        var stateSerialization: CKSyncEngine.State.Serialization?
    }
    private var syncState: SyncState
    
    private let changeStream: ChangeStream
    private var monitorTask: Task<(), Never>!
        
    public init(id: String, forkedResource: ForkedResource<R>, cloudKitContainer: CKContainer = .default()) throws {
        self.id = id
        self.forkedResource = forkedResource
        self.changeStream = forkedResource.changeStream
        self.cloudKitContainer = cloudKitContainer
        let dirURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(component: "CloudKitExchange")
        self.dataURL = dirURL
            .appending(component: id)
            .appendingPathExtension("json")

        if !FileManager.default.fileExists(atPath: dirURL.path()) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        
        // Restore state
        let stateData = (try? Data(contentsOf: dataURL)) ?? Data()
        self.syncState = (try? JSONDecoder().decode(SyncState.self, from: stateData)) ?? SyncState()
        
        // Setup engine
        let configuration: CKSyncEngine.Configuration =
            .init(
                database: cloudKitContainer.privateCloudDatabase,
                stateSerialization: self.syncState.stateSerialization,
                delegate: self
            )
        engine = CKSyncEngine(configuration)
        
        // Fork for sync
        try createForks()
        
        // Monitor changes to main
        monitorTask = Task { [weak self, changeStream] in
            self?.uploadMainIfNeeded()
            for await _ in changeStream.filter({ $0.fork == .main && ![.cloudKitDownload, .cloudKitUpload].contains($0.mergingFork) }) {
                guard let self else { break }
                self.uploadMainIfNeeded()
            }
        }
    }
    
    deinit {
        monitorTask.cancel()
    }
    
    private func uploadMainIfNeeded() {
        do {
            try forkedResource.performAtomically {
                if try forkedResource.hasUnmergedCommitsInMain(for: .cloudKitUpload) {
                    try forkedResource.mergeFromMain(into: .cloudKitUpload)
                    let content = try forkedResource.content(of: .cloudKitUpload)
                    if case .none = content {
                        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
                    } else {
                        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    }
                }
            }
        } catch {
            Logger.exchange.error("Failure monitoring changes: \(error)")
        }
    }
    
    internal func saveState() {
        do {
            let data = try JSONEncoder().encode(syncState)
            try data.write(to: dataURL)
        } catch {
            Logger.exchange.error("Failed to save state")
        }
    }
}

internal extension CloudKitExchange {
    
    nonisolated func createForks() throws {
        for fork in [Fork.cloudKitUpload, .cloudKitDownload] where !forkedResource.has(fork) {
            try forkedResource.create(fork)
        }
    }
    
    nonisolated func removeForks() throws {
        for fork in [Fork.cloudKitUpload, .cloudKitDownload] where forkedResource.has(fork) {
            try forkedResource.mergeIntoMain(from: fork)
            try forkedResource.delete(fork)
        }
    }
    
}

@available(iOS 17.0, tvOS 17.0, watchOS 9.0, macOS 14.0, *)
extension CloudKitExchange: CKSyncEngineDelegate {
    
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            syncState.stateSerialization = event.stateSerialization
            saveState()
        case .accountChange(let event):
            handleAccountChange(event)
        case .fetchedDatabaseChanges(let event):
            handleFetchedDatabaseChanges(event)
        case .fetchedRecordZoneChanges(let event):
            handleFetchedRecordZoneChanges(event)
        case .sentRecordZoneChanges(let event):
            handleSentRecordZoneChanges(event)
        case .sentDatabaseChanges:
            break
        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges, .willSendChanges, .didSendChanges:
            break
        @unknown default:
            Logger.exchange.info("Received unknown event: \(event)")
        }
    }
    
    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { recordID in
            guard recordID.recordName == id else { return nil }
            do {
                if let resourceValue = try forkedResource.resource(of: .cloudKitUpload) {
                    let record = (try? await syncEngine.database.record(for: recordID)) ?? CKRecord(recordType: recordType, recordID: recordID)
                    let data = try JSONEncoder().encode(resourceValue)
                    record.encryptedValues[CKRecord.resourceDataKey] = data
                    return record
                } else {
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    return nil
                }
            } catch {
                Logger.exchange.error("Error while preparing batch of changes: \(error)")
                return nil
            }
        }
    }
    
}
