//
//  TeamInvite.swift
//  Kryptonite
//
//  Created by Alex Grinman on 7/20/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation

enum TeamJoinType {
    case invite(TeamInvite)
    case create(Request, Session)
    case createFromApp(String)
}

struct TeamInvite {
    let initialTeamPublicKey:SodiumSignPublicKey
    let blockHash:Data
    let seed:Data
    
    enum Errors:Error {
        case missingArgs
    }
    
    init(initialTeamPublicKey:SodiumSignPublicKey, blockHash:Data, seed:Data) {
        self.initialTeamPublicKey = initialTeamPublicKey
        self.blockHash = blockHash
        self.seed = seed
    }
    
    init(path:[String]) throws {
        guard path.count >= 3 else {
            throw Errors.missingArgs
        }
        
        let initialTeamPublicKey = try SodiumSignPublicKey(path[0].fromBase64())
        let blockHash = try SodiumSignPublicKey(path[1].fromBase64())
        let seed = try path[2].fromBase64()
        
        self.init(initialTeamPublicKey: initialTeamPublicKey, blockHash: blockHash, seed: seed)
    }
    
    var path:[String] {
        return [initialTeamPublicKey.toBase64(true), blockHash.toBase64(true), seed.toBase64(true)]
    }
}
