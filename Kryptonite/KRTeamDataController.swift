//
//  KRTeamDataController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/25/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UIKit

protocol KRTeamDataControllerDelegate {
    var identity:TeamIdentity { get set }
    var refreshControl:UIRefreshControl? { get }
    var controller:UIViewController { get }
    
    func didUpdateTeamIdentity()
    func update(identity:TeamIdentity)
}

extension KRTeamDataControllerDelegate {
    
    func fetchTeamUpdates() {
        do {
            try TeamService.shared().getVerifiedTeamUpdates { (result) in
                
                dispatchMain { self.refreshControl?.endRefreshing() }

                switch result {
                case .error(let e):
                    self.controller.showWarning(title: "Error", body: "Could not fetch new team updates. \(e).")
                    
                case .result(let service):
                    self.update(identity: service.teamIdentity)
                    
                    do {
                        try IdentityManager.commitTeamChanges(identity: service.teamIdentity)
                    } catch {
                        self.controller.showWarning(title: "Error", body: "Could not save team updates. \(error).")
                        return
                    }
                    
                    self.didUpdateTeamIdentity()
                }
            }
        } catch {
            controller.showWarning(title: "Error", body: "Could attempting to fetch new team updates. \(error).")
        }
    }
}

