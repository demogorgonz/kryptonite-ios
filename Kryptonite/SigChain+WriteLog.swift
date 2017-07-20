//
//  SigChain+WriteLog.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/25/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation


enum AuditLogSendingErrors:Error {
    case loggingDisabled
}

extension TeamIdentity {
    
    /**
     Write and Send a team audit log
     
     - parameters:
         - teamIdentity: the team identity to send the log as
         - log: the log data to send
     */
    mutating func writeAndSendLog(auditLog:Audit.Log) throws {
        
        // check if logging is enabled
        guard  try self.team().commandEncryptedLoggingEnabled
        else {
            throw AuditLogSendingErrors.loggingDisabled
        }
        
        let logData = try auditLog.jsonData()
        try self.writeLog(data: logData)
        try IdentityManager.commitTeamChanges(identity: self)
        
        try sendUnsentAuditLogs()
    }
    
    /**
     Write audit log data to the LogChain
     
     - parameters:
         - teamIdentity: the team identity to send the log as
         - log: the log data to send
     */
    mutating func writeLog(data:Data) throws {
        //TODO: check indeed that this last block hash reflects what's in the database
        guard let lastLogBlockHash = self.logCheckpoint else {
            throw SigChain.Errors.missingLastLogBlockHash
        }
        
        guard let logCiphertext:Data = KRSodium.instance().secretBox.seal(message: data, secretKey: self.logEncryptionKey) else {
            throw SigChain.Errors.logEncryptionFailed
        }
        
        let encryptedLog = SigChain.LogOperation.encryptLog(SigChain.EncryptedLog(ciphertext: logCiphertext))
        let appendLogBLock = SigChain.AppendLogBlock(lastBlockHash: lastLogBlockHash, operation: encryptedLog)
        let payload = SigChain.Payload.appendLogBlock(appendLogBLock)
        let payloadData = try payload.jsonData()
        
        // sign the payload
        guard let payloadSignature = KRSodium.instance().sign.signature(message: payloadData, secretKey: self.keyPair.secretKey)
            else {
                throw SigChain.Errors.payloadSignatureFailed
        }
        
        // send the payload request
        let payloadDataString = try payloadData.utf8String()
        
        // add the log block
        let logBlock = SigChain.LogBlock(payload: payloadDataString, signature: payloadSignature, log: logCiphertext)
        try dataManager.appendLog(block: logBlock)
        self.logCheckpoint = logBlock.hash()
    }
}


