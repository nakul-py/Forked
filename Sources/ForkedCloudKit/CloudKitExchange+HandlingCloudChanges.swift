//
//  CloudKitExchange+HandlingCloudChanges.swift
//  Forked
//
//  Created by Drew McCormack on 27/08/2024.
//
import CloudKit
import Forked
import os.log

@available(iOS 17.0, tvOS 17.0, watchOS 9.0, macOS 14.0, *)
extension CloudKitExchange {
    
    func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        do {
            try forkedResource.performAtomically {
                switch event.changeType {
                case .signIn, .switchAccounts:
                    try removeForks()
                    try createForks()
                case .signOut:
                    try removeForks()
                @unknown default:
                    Logger.exchange.log("Unknown account change type: \(event)")
                }
            }
        } catch {
            Logger.exchange.error("Failure during handling of account change: \(error)")
        }
    }
    
    func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in event.deletions {
            switch deletion.zoneID.zoneName {
            case zoneID.zoneName:
                do {
                    try removeForks()
                } catch {
                    Logger.exchange.error("Failed to delete content when zone removed: \(error)")
                }
            default:
                Logger.exchange.info("Received deletion for unknown zone: \(deletion.zoneID)")
            }
        }
    }
    
    func handleFetchedRecordZoneChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        for modification in event.modifications {
            update(withDownloadedRecord: modification.record)
        }
        
        for deletion in event.deletions {
            let id = deletion.recordID.recordName
            guard self.id == id else { continue }
            do {
                try forkedResource.removeContent(from: .cloudKitDownload)
                try forkedResource.mergeIntoMain(from: .cloudKitDownload)
            } catch {
                Logger.exchange.error("Failed to update resource with downloaded data: \(error)")
            }
        }
    }
    
    func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        for failedRecordSave in event.failedRecordSaves {
            let failedRecord = failedRecordSave.record
            let id = failedRecord.recordID.recordName
            guard self.id == id else { continue }
            
            switch failedRecordSave.error.code {
            case .serverRecordChanged:
                guard let serverRecord = failedRecordSave.error.serverRecord else {
                    Logger.exchange.error("No server record for conflict \(failedRecordSave.error)")
                    continue
                }
                update(withDownloadedRecord: serverRecord)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(failedRecord.recordID)])
            case .zoneNotFound:
                do {
                    try removeForks()
                    try createForks()
                    let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                    engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
                    engine.state.add(pendingRecordZoneChanges: [.saveRecord(failedRecord.recordID)])
                } catch {
                    Logger.exchange.error("Failed to recover from missing zone: \(error)")
                }
            case .unknownItem:
                // May be deleted by other device. Let that deletion propagate naturally.
                Logger.exchange.error("Unknown item error following upload. Ignoring: \(failedRecordSave.error)")
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled:
                Logger.exchange.debug("Retryable error saving \(failedRecord.recordID): \(failedRecordSave.error)")
            default:
                Logger.exchange.fault("Unknown error saving record \(failedRecord.recordID): \(failedRecordSave.error)")
            }
        }
    }
    
    func update(withDownloadedRecord record: CKRecord) {
        let id = record.recordID.recordName
        guard self.id == id else { return }
        
        guard let data = record.encryptedValues[CKRecord.resourceDataKey] as? Data else {
            Logger.exchange.error("No data found in CKRecord")
            return
        }
        
        do {
            let resource = try JSONDecoder().decode(R.Resource.self, from: data)
            try forkedResource.update(.cloudKitDownload, with: resource)
            try forkedResource.mergeIntoMain(from: .cloudKitDownload)
        } catch {
            Logger.exchange.error("Failed to update resource with downloaded data: \(error)")
        }
    }
    
}

