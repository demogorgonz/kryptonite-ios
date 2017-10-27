//
//  TeamActvitiyController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/25/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UIKit

class TeamActivityController: KRBaseTableController {

    
    var identity:TeamIdentity!    
    var blocks:[SigChain.Payload] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Team Activity"
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 70
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return blocks.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TeamEventLogCell") as! TeamEventLogCell
        cell.set(payload: blocks[indexPath.row], index: indexPath.row, count: blocks.count)
        
        return cell
    }

}

extension SigChain.TeamPointer:CustomStringConvertible {
    var description:String {
        switch self {
        case .publicKey(let pub):
            return "public key \(pub.toBase64())"
        case .lastBlockHash(let hash):
            return "block hash \(hash.toBase64())"
        }
    }
}

extension SigChain.Payload {
    
    var eventLogDetails:(title:String, detail:String) {
        switch self {
        case .readBlocks(let read):
            return ("read", "get \(read.teamPointer)")
            
        case .createChain(let create):
            return ("create chain", "start team \"\(create.teamInfo.name)\"\nby creator \(create.creator.email)")
            
        case .appendBlock(let append):
            switch append.operation {
            case .inviteMember(let invite):
                return ("invite member", "invitation \(invite.noncePublicKey.toBase64())")
                
            case .acceptInvite(let member):
                return ("accept invite", "\(member.email) joined")
                
            case .addMember(let member):
                return ("add member", "\(member.email) was added")
                
            case .removeMember(let memberPublicKey):
                return ("remove member", "\(memberPublicKey.toBase64()) removed")
                
            case .cancelInvite(let invite):
                return ("cancel invite", "\(invite.noncePublicKey.toBase64()) canceled")
                
            case .setPolicy(let policy):
                return ("set policy", "temporary approval \(policy.description)")
                
            case .setTeamInfo(let teamInfo):
                return ("set team info", "team name \"\(teamInfo.name)\"")
                
            case .pinHostKey(let host):
                return ("pin ssh host key", "host \"\(host.host)\"\n\(host.displayPublicKey)")
                
            case .unpinHostKey(let host):
                return ("unpin ssh host key", "host \"\(host.host)\"\n\(host.displayPublicKey)")
                
            case .addLoggingEndpoint(let endpoint):
                return ("enable logging", "endpoint \(endpoint)")
                
            case .removeLoggingEndpoint(let endpoint):
                return ("disable logging", "endpoint \(endpoint)")
                
            case .addAdmin(let admin):
                return ("make admin", "id \(admin.toBase64())")
                
            case .removeAdmin(let admin):
                return ("remove admin", "id \(admin.toBase64())")
            }
        case .createLogChain(let logChain):
            return ("create log chain", "started encrypted log chain (\(logChain.wrappedKeys.count) admins)")
            
        case .readLogBlocks(let readLogs):
            return ("read logs", "get \(readLogs.teamPointer)")
            
        case .appendLogBlock(let appendLog):
            switch appendLog.operation {
            case .addWrappedKeys(let wrappedKeys):
                return ("give new admin(s) log access", "\(wrappedKeys.count) admins")
            case .rotateKey(let wrappedKeys):
                return ("rotate log access keys", "rotated for \(wrappedKeys.count) admins")
            case .encryptLog:
                return ("write new encrypted log", "")
            }
            
        }
        
    }
}


class TeamEventLogCell:UITableViewCell {
    @IBOutlet weak var eventName:UILabel!
    @IBOutlet weak var eventDetail:UILabel!
    
    @IBOutlet weak var topLine:UIView!
    @IBOutlet weak var bottomLine:UIView!
    
    func set(payload:SigChain.Payload, index:Int, count:Int) {
        let (title, detail) = payload.eventLogDetails
        eventName.text = title
        eventDetail.text = detail
        
        switch index {
        case let x where x == 0 && x == count - 1:
            bottomLine.isHidden = true
            topLine.isHidden = true
        case 0:
            bottomLine.isHidden = false
            topLine.isHidden = true
        case count - 1:
            bottomLine.isHidden = true
            topLine.isHidden = false
        default:
            bottomLine.isHidden = false
            topLine.isHidden = false
        }
    }
}
