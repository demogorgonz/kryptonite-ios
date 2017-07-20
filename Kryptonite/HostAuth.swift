//
//  HostAuth.swift
//  Kryptonite
//
//  Created by Kevin King on 2/16/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import JSON

struct VerifiedHostAuth:JsonWritable {
    let hostName:String
    private let hostAuth:HostAuth
    
    var hostKey:Data {
        return hostAuth.hostKey
    }
    
    var signature:Data {
        return hostAuth.signature
    }
    
    var object:Object {
        return hostAuth.object
    }
    
    enum Errors:Error {
        case invalidSignature
        case missingHostName
    }
    struct InvalidSignature:Error{}
    struct MissingHostName:Error{}

    init(session:Data, hostAuth:HostAuth) throws {
        guard try hostAuth.verify(session: session) else {
            throw Errors.invalidSignature
        }
        
        guard let hostName = hostAuth.hostNames.first else {
            throw Errors.missingHostName
        }
        
        self.hostName = hostName
        self.hostAuth = hostAuth
    }
}

struct HostAuth:Jsonable{
    let hostKey: Data
    let signature: Data
    let hostNames: [String]
    
    init(hostKey: Data, signature: Data, hostNames: [String]) {
        self.hostKey = hostKey
        self.signature = signature
        self.hostNames = hostNames
    }
    
    public init(json: Object) throws {
        hostKey = try ((json ~> "host_key") as String).fromBase64()
        signature = try ((json ~> "signature") as String).fromBase64()
        hostNames = try json ~> "host_names"
    }
    public var object: Object {
        var json:[String:Any] = [:]
        json["host_key"] = hostKey.toBase64()
        json["signature"] = signature.toBase64()
        json["host_names"] = hostNames
        return json
    }
    
    func verify(session: Data) throws -> Bool {
        var hostKeyData = Data(hostKey)
        let keyBytes = hostKeyData.withUnsafeMutableBytes{ (bytes: UnsafeMutablePointer<UInt8>) in
            return bytes
        }
        
        var sigData = Data(signature)
        let sigBytes = sigData.withUnsafeMutableBytes{ (bytes: UnsafeMutablePointer<UInt8>) in
            return bytes
        }
        var sessionClone = Data(session)
        let signDataBytes = sessionClone.withUnsafeMutableBytes({ (bytes: UnsafeMutablePointer<UInt8>) in
            return bytes
        })
        let result = kr_verify_signature(keyBytes, hostKeyData.count, sigBytes, sigData.count, signDataBytes, sessionClone.count)
        if result == 1 {
            return true
        }
        return false
    }
}
