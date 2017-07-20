//
//  Silo.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/8/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation
import JSON
import AwesomeCache


struct UserRejectedError:Error, CustomDebugStringConvertible {
    static let rejectedConstant = "rejected"
    
    var debugDescription:String {
        return UserRejectedError.rejectedConstant
    }
    
    static func isRejected(errorString:String) -> Bool {
        return errorString == rejectedConstant
    }
}


typealias CacheKey = String
extension CacheKey {
    init(_ session:Session, _ request:Request) {
        self = "\(session.id)_\(request.id)"
    }
}

class Silo {
    
    var mutex = Mutex()

    var requestCache: Cache<NSData>?
    //  store requests waiting for user approval
    var pendingRequests: Cache<NSString>?
    
    // singelton
    private static var sharedSiloMutex = Mutex()
    private static var sharedSilo:Silo?
    class var shared:Silo {
        defer { sharedSiloMutex.unlock() }
        sharedSiloMutex.lock()
        
        guard let ss = sharedSilo else {
            sharedSilo = Silo()
            return sharedSilo!
        }
        return ss
    }

    
    init() {
        requestCache = try? Cache<NSData>(name: "silo_cache", directory: sharedDirectory)
        pendingRequests = try? Cache<NSString>(name: "silo_pending_requests", directory: sharedDirectory)
    }
    
    lazy var sharedDirectory:URL? = {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupSecurityID)?.appendingPathComponent("cache")
    }()
    
    enum Errors:Error {
        case invalidRequestTime
        case requestPending
        case responseNotNeeded
        case siloCacheCreation
        case noTeamIdentity
    }
    
    //MARK: Handle Logic
    func handle(request:Request, session:Session, communicationMedium: CommunicationMedium, completionHandler: (()->Void)? = nil) throws {
        mutex.lock()
        defer { mutex.unlock() }

        // ensure session is still active
        guard let _ = SessionManager.shared.get(id: session.id) else {
            throw SessionRemovedError()
        }
        
        // ensure request has not expired
        let now = Date().timeIntervalSince1970
        if abs(now - Double(request.unixSeconds)) > Properties.requestTimeTolerance {
            throw Silo.Errors.invalidRequestTime
        }
        
        // check if the request has already been received and cached
        requestCache?.removeExpiredObjects()
        if  let cachedResponseData = requestCache?[CacheKey(session, request)] as Data? {
            let json:Object = try JSON.parse(data: cachedResponseData)
            let response = try Response(json: json)
            try TransportControl.shared.send(response, for: session, completionHandler: completionHandler)
            return
        }
        
        // check if the request has already been received, but is still pending
        pendingRequests?.removeExpiredObjects()
        if pendingRequests?.object(forKey: CacheKey(session, request)) != nil {
            throw Silo.Errors.requestPending
        }
                
        // decide if request body can be responded to immediately
        // or doesn't need response,
        // or needs user's approval first
        switch request.body {
        case .unpair:
            Analytics.postEvent(category: "device", action: "unpair", label: "request")
            
            SessionManager.shared.remove(session: session)
            TransportControl.shared.remove(session: session, sendUnpairResponse: false)
            
            throw SessionRemovedError()
            
        case .noOp:
            return
            
        case .decryptLog,
             .teamOperation,
             .readTeam,
             .createTeam,
             .ssh where Policy.needsUserApproval(for: session, and: request.body),
             .git where Policy.needsUserApproval(for: session, and: request.body):
            
            // record this request as pending
            pendingRequests?.setObject("", forKey: CacheKey(session, request), expires: .seconds(Properties.requestTimeTolerance * 2))

            try handleRequestRequiresApproval(request: request, session: session, communicationMedium: communicationMedium, completionHandler: completionHandler)
            return
            
        case .me, .ssh, .git:
            break
        }

        // otherwise, continue with creating and sending the response
        let response = try responseFor(request: request, session: session, signatureAllowed: true)
        
        // analytics / notify user on error for signature response
        switch response.body {
        case .ssh(let sign):
            Analytics.postEvent(category: request.body.analyticsCategory, action: "automatic approval", label: communicationMedium.rawValue)
            
            if let error = sign.error {
                Policy.notifyUser(errorMessage: error, session: session)
            } else {
                Policy.notifyUser(session: session, request: request)
            }
            
            if case .ssh(let sshRequest) = request.body, sshRequest.verifiedHostAuth == nil {
                Analytics.postEvent(category: "host", action: "unknown")
            }

        case .git(let gitSign):
            Analytics.postEvent(category: request.body.analyticsCategory, action: "automatic approval", label: communicationMedium.rawValue)
            
            if let error = gitSign.error {
                Policy.notifyUser(errorMessage: error, session: session)
            } else {
                Policy.notifyUser(session: session, request: request)
            }

        case .decryptLog, .teamOperation, .readTeam, .createTeam, .me, .ack, .unpair:
            break
        }
        
        try TransportControl.shared.send(response, for: session, completionHandler: completionHandler)
    }

    func handleRequestRequiresApproval(request: Request, session: Session, communicationMedium: CommunicationMedium, completionHandler: (() -> ())?) throws {
        
        Policy.addPendingAuthorization(session: session, request: request)
        Policy.requestUserAuthorization(session: session, request: request)
        
        if request.sendACK {
            let arn = API.endpointARN ?? ""
            let ack = Response(requestID: request.id, endpoint: arn, body: .ack(.ok(AckResponse())), approvedUntil: Policy.approvedUntilUnixSeconds(for: session), trackingID: (Analytics.enabled ? Analytics.userID : "disabled"))
            do {
                try TransportControl.shared.send(ack, for: session)
            } catch (let e) {
                log("ack send error \(e)")
            }
        }
        
        Analytics.postEvent(category: request.body.analyticsCategory, action: "requires approval", label:communicationMedium.rawValue)
        completionHandler?()
    }
    
    // MARK: Pending
    func removePending(request:Request, for session:Session) {
        mutex.lock()
        defer { mutex.unlock() }
        
        pendingRequests?.removeObject(forKey: CacheKey(session, request))
    }
    
    func isPending(request:Request, for session:Session) -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        
        pendingRequests?.removeExpiredObjects()
        if pendingRequests?.object(forKey: CacheKey(session, request)) != nil {
            return true
        }
        
        return false
    }

    
    // MARK: Response
    
    func lockResponseFor(request:Request, session:Session, signatureAllowed:Bool) throws -> Response {
        mutex.lock()
        defer { mutex.unlock() }
        return try responseFor(request: request, session: session, signatureAllowed: signatureAllowed)
    }
    
    // precondition: mutex locked
    private func responseFor(request:Request, session:Session, signatureAllowed:Bool) throws -> Response {
        let requestStart = Date().timeIntervalSince1970
        defer { log("response took \(Date().timeIntervalSince1970 - requestStart) seconds") }
        
        // the response type
        var responseType:ResponseBody
        var auditLog:Audit.Log?
        
        // craft a response to the request type
        // given the user's approval: `signatureAllowed`
        switch request.body {
        case .ssh(let signRequest):
            let kp = try KeyManager.sharedInstance()
            
            if try kp.keyPair.publicKey.fingerprint() != signRequest.fingerprint.fromBase64() {
                throw KeyManager.Errors.keyDoesNotExist
            }
            
            var result:ResponseResult<SSHSignResponse>
            var sshAuditLogResult:Audit.SSHSignature.Result
            
            do {
                
                if signatureAllowed {
                    
                    // team known hosts
                    // if team exists then check for pinned known hosts
                    if  let verifiedHostAuth = signRequest.verifiedHostAuth,
                        let teamIdentity = (try? IdentityManager.getTeamIdentity()) as? TeamIdentity
                    {
                        try teamIdentity.dataManager.check(verifiedHost: verifiedHostAuth)
                    }
                    
                    // local known hosts
                    // if host auth provided, check known hosts
                    // fails in invalid signature -or- hostname not provided
                    if let verifiedHostAuth = signRequest.verifiedHostAuth {
                        try KnownHostManager.shared.checkOrAdd(verifiedHostAuth: verifiedHostAuth)
                    }
                    
                    // only place where signature should occur
                    let signature = try kp.keyPair.signAppendingSSHWirePubkeyToPayload(data: signRequest.data, digestType: signRequest.digestType.based(on: request.version))
                    
                    result = .ok(SSHSignResponse(signature: signature.toBase64()))
                    
                    sshAuditLogResult = .signature(signature)
                    
                } else {
                    throw UserRejectedError()
                }
                
            }
            catch let error as UserRejectedError {
                result = .error("\(error)")
                sshAuditLogResult = .userRejected

            }
            catch let error as HostMistmatchError {
                result = .error("\(error)")
                sshAuditLogResult = .hostMismatch(error.expectedPublicKeys)
            }
            catch {
                result = .error("\(error)")
                sshAuditLogResult = .error("\(error)")
            }
            
            //create the audit log
            let logBody = Audit.LogBody.ssh(Audit.SSHSignature(user: signRequest.user,
                                                               verifiedHostAuth: signRequest.verifiedHostAuth ,
                                                               sessionData: signRequest.session,
                                                               result: sshAuditLogResult))
            
            auditLog = Audit.Log(session: Audit.Session(deviceName: session.pairing.name,
                                                        workstationPublicKeyDoubleHash: session.pairing.workstationPublicKeyDoubleHash),
                                 body: logBody)
            
            // set the response
            responseType = .ssh(result)

            
        case .git(let gitSignRequest):
            var result:ResponseResult<GitSignResponse>
            var logBody:Audit.LogBody
            
            do {
                if signatureAllowed {
                    // only place where git signature should occur
                    let keyManager = try KeyManager.sharedInstance()
                    
                    let keyID = try keyManager.getPGPPublicKeyID()                    
                    let _ = keyManager.updatePGPUserIDPreferences(for: gitSignRequest.userId)

                    switch gitSignRequest.git {
                    case .commit(let commit):
                        
                        let asciiArmoredSig = try keyManager.keyPair.signGitCommit(with: commit, keyID: keyID)
                        let signature = asciiArmoredSig.packetData
                        result = .ok(GitSignResponse(signature: signature.toBase64()))
                        
                        logBody = .gitCommit(Audit.GitCommitSignature(commitInfo: commit, result: .signature(signature)))
                        
                    case .tag(let tag):
                        
                        let signature = try keyManager.keyPair.signGitTag(with: tag, keyID: keyID).packetData
                        result = .ok(GitSignResponse(signature: signature.toBase64()))

                        logBody = .gitTag(Audit.GitTagSignature(tagInfo: tag, result: .signature(signature)))
                    }
                    
                } else {
                    switch gitSignRequest.git {
                    case .commit(let commit):
                        logBody = .gitCommit(Audit.GitCommitSignature(commitInfo: commit, result: .userRejected))
                    case .tag(let tag):
                        logBody = .gitTag(Audit.GitTagSignature(tagInfo: tag, result: .userRejected))
                    }
                    
                    throw UserRejectedError()
                }
                
            }  catch {
                result = .error("\(error)")
                
                switch gitSignRequest.git {
                case .commit(let commit):
                    logBody = .gitCommit(Audit.GitCommitSignature(commitInfo: commit, result: .error("\(error)")))
                case .tag(let tag):
                    logBody = .gitTag(Audit.GitTagSignature(tagInfo: tag, result: .error("\(error)")))
                }
            }
            
            // create the audit log
            auditLog = Audit.Log(session: Audit.Session(deviceName: session.pairing.name,
                                                        workstationPublicKeyDoubleHash: session.pairing.workstationPublicKeyDoubleHash),
                                 body: logBody)

            // set the response 
            responseType = .git(result)
            
        case .me(let meRequest):
            let keyManager = try KeyManager.sharedInstance()
            
            var pgpPublicKey:Data?
            if let pgpUserID = meRequest.pgpUserId {
                pgpPublicKey = try keyManager.loadPGPPublicKey(for: pgpUserID).packetData
            }

            var teamCheckpoint:TeamCheckpoint?
            if let identity = try IdentityManager.getTeamIdentity() {
                teamCheckpoint =  TeamCheckpoint(publicKey: identity.keyPair.publicKey,
                                                 teamPublicKey: identity.initialTeamPublicKey,
                                                 lastBlockHash: identity.checkpoint)

            }
            
            let me = MeResponse(me: MeResponse.Me(email: try IdentityManager.getMe(),
                                                  publicKeyWire: try keyManager.keyPair.publicKey.wireFormat(),
                                                  pgpPublicKey: pgpPublicKey,
                                                  teamCheckpoint: teamCheckpoint))
            responseType = .me(.ok(me))
            
        case .readTeam(let readTeamRequest):
            
            guard let teamIdentity = try IdentityManager.getTeamIdentity() else {
                throw Errors.noTeamIdentity
            }
            
            guard signatureAllowed else {
                responseType = .readTeam(.error("rejected"))
                break
            }
            
            do {
                //TODO: decide exp time
                let expiration = Date().timeIntervalSince1970 + TimeSeconds.hour.multiplied(by: 1)
                let timeReadToken = ReadToken.time(TimeToken(readerPublicKey: readTeamRequest.publicKey, expiration: UInt64(expiration)))
                let timeReadTokenData = try timeReadToken.jsonData()
                
                guard let signature = KRSodium.instance().sign.signature(message: timeReadTokenData, secretKey: teamIdentity.keyPair.secretKey)
                    else {
                        throw CryptoError.sign(.Ed25519, nil)
                }
                

                let timeReadTokenString = try timeReadTokenData.utf8String()
                
                responseType = .readTeam(.ok(ReadTeamResponse(signerPublicKey: teamIdentity.keyPair.publicKey,
                                                              token: timeReadTokenString,
                                                              signature: signature)))

            } catch {
                responseType = .readTeam(.error("\(error)"))
            }
        case .teamOperation(let teamOperationRequest):
            guard IdentityManager.hasTeam() else {
                throw Errors.noTeamIdentity
            }
            
            guard signatureAllowed else {
                responseType = .teamOperation(.error("rejected"))
                break
            }
            
            do {
                // create the new block
                let (service, response) = try TeamService.shared().responseFor(requestableOperation: teamOperationRequest.operation)
                
                // commit team changes
                try IdentityManager.commitTeamChanges(identity: service.teamIdentity)
                
                // return the `ok` response
                responseType = .teamOperation(.ok(response))
            } catch {
                responseType = .teamOperation(.error("\(error)"))
            }
            
        case .decryptLog(let decryptLogRequest):
            guard let teamIdentity:TeamIdentity = try IdentityManager.getTeamIdentity() else {
                throw Errors.noTeamIdentity
            }
            
            // ensure we're allowed to decrypt
            guard signatureAllowed else {
                responseType = .decryptLog(.error("rejected"))
                break
            }
            
            guard decryptLogRequest.wrappedKey.publicKey == teamIdentity.encryptionKeyPair.publicKey else {
                responseType = .decryptLog(.error("public key mismatch"))
                break
            }
            
            guard let unwrappedKey = KRSodium.instance().box.open(anonymousCipherText: decryptLogRequest.wrappedKey.ciphertext,
                                                                  recipientPublicKey: teamIdentity.encryptionKeyPair.publicKey,
                                                                  recipientSecretKey: teamIdentity.encryptionKeyPair.secretKey)
            else {
                    responseType = .decryptLog(.error("invalid ciphertext"))
                    break
            }
            
            responseType = .decryptLog(.ok(LogDecryptionResponse(logDecryptionKey: unwrappedKey)))
        
        case .createTeam, .noOp, .unpair:
            throw Silo.Errors.responseNotNeeded
        }
        
        // save the audit log if we have one
        if let auditLog = auditLog {
            
            // local
            LogManager.shared.save(auditLog: auditLog, sessionID: session.id)
            
            // remote only if we have a team identity
            if var teamIdentity:TeamIdentity = try IdentityManager.getTeamIdentity() {
                do {
                    // try to write & save a team audit log
                    try teamIdentity.writeAndSendLog(auditLog: auditLog)
                } catch {
                    log("error saving team audit log: \(error)", .error)
                }
            }
        }
        
        // create the response and return it
        let arn = API.endpointARN ?? ""
        
        let response = Response(requestID: request.id,
                                endpoint: arn,
                                body: responseType,
                                approvedUntil: Policy.approvedUntilUnixSeconds(for: session),
                                trackingID: (Analytics.enabled ? Analytics.userID : "disabled"))
        
        let responseData = try response.jsonData()
        requestCache?.setObject(responseData as NSData, forKey: CacheKey(session, request), expires: .seconds(Properties.requestTimeTolerance * 2))
        
        return response
    }
    
    func cachedResponse(for session:Session,with request:Request) -> Response? {
        if  let cachedResponseData = requestCache?[CacheKey(session, request)] as Data?,
            let json:Object = try? JSON.parse(data: cachedResponseData),
            let response = try? Response(json: json)
        {
            return response
        }

        return nil
    }

}
