//
//  KnownHost.swift
//  Kryptonite
//
//  Created by Alex Grinman on 4/27/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import JSON

struct SSHHostKey:Jsonable {
    let host:String
    let publicKey:SSHWireFormat
    
    init(host:String, publicKey:SSHWireFormat) {
        self.host = host
        self.publicKey = publicKey
    }
    
    init(json: Object) throws {
        try self.init(host: json ~> "host",
                      publicKey: ((json ~> "public_key") as String).fromBase64())
    }
    
    var object: Object {
        return ["host": host,
                "public_key": publicKey.toBase64()]
    }
    
    var displayPublicKey:String {
        return (try? publicKey.toAuthorized()) ?? publicKey.toBase64()
    }
}

struct KnownHost {
    var hostName:String
    var publicKey:SSHWireFormat
    var dateAdded:Date
    
    init(sshHostKey:SSHHostKey) {
        self.hostName = sshHostKey.host
        self.publicKey = sshHostKey.publicKey
        self.dateAdded = Date()
    }
    
    init(hostName:String, publicKey:SSHWireFormat, dateAdded:Date = Date()) {
        self.hostName  = hostName
        self.publicKey = publicKey
        self.dateAdded = dateAdded
    }
    
    func sshHostKey() throws -> SSHHostKey {
        return SSHHostKey(host: hostName, publicKey: publicKey)
    }
}

func ==(l:KnownHost, r:KnownHost) -> Bool {
    return l.hostName == r.hostName && l.publicKey == r.publicKey
}
