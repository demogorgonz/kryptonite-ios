//
//  TeamAuditLog+Send.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/23/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation

func sendUnsentAuditLogs() throws {
    try TeamService.shared().sendUnsentLogBlocks { result in
        switch result {
        case .error(let e):
            log("could not send log block: \(e)", .error)
            
        case .result:
            log("log blocks not sent ")
        }
    }

}

