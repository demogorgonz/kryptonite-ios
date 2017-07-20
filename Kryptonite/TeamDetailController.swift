//
//  TeamDetailController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 7/22/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import UIKit
import LocalAuthentication


class TeamDetailController: KRBaseTableController, KRTeamDataControllerDelegate {
    
    @IBOutlet weak var teamLabel:UILabel!
    @IBOutlet weak var emailLabel:UILabel!
    @IBOutlet weak var leaveTeamButton:UIButton!
    @IBOutlet weak var headerView:UIView!
    
    @IBOutlet weak var activityDetailLabel:UILabel!
    @IBOutlet weak var membersDetailLabel:UILabel!
    @IBOutlet weak var hostsDetailLabel:UILabel!

    @IBOutlet weak var approvalWindowAttributeLabel:UILabel!
    @IBOutlet weak var approvalWindowLabel:UILabel!
    
    var _teamIdentity:TeamIdentity!
    var identity: TeamIdentity {
        get {
            return _teamIdentity
        } set (id) {
            _teamIdentity = id
        }
    }

    var team:Team?
    var isAdmin:Bool = false
    
    var blocks:[SigChain.Payload] = []
    var members:[Team.MemberIdentity] = []
    var hosts:[SSHHostKey] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = try? identity.team().name
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 70
        
        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor.app
        refresh.addTarget(self, action: #selector(TeamDetailController.doFetchTeamUpdates), for: UIControlEvents.valueChanged)
        tableView.refreshControl = refresh
        
        didUpdateTeamIdentity()
    }
    
    @objc dynamic func doFetchTeamUpdates() {
        self.fetchTeamUpdates()
    }
    
    func didUpdateTeamIdentity() {
        dispatchMain {
            self.emailLabel.text = self.identity.email

            do {
                let team = try self.identity.team()
                self.teamLabel.text = team.name
                self.approvalWindowLabel.text = team.policy.description
                self.team = team
                
                self.isAdmin = try self.identity.isAdmin()
                
                if self.isAdmin {
                    self.emailLabel.text = self.identity.email + " (owner)"
                }
                
                // pre-fetch team lists
                self.blocks = try self.identity.dataManager.fetchAll().map {
                    try SigChain.Payload(jsonString: $0.payload)
                }
                self.members = try self.identity.dataManager.fetchAll()
                self.hosts = try self.identity.dataManager.fetchAll()
                
                // set activity label
                let blocksCount = self.blocks.count
                let blocksSuffix = blocksCount == 1 ? "" : "s"
                self.activityDetailLabel.text = "\(blocksCount) event\(blocksSuffix)"
                
                let membersCount = self.members.count
                let membersSuffix = membersCount == 1 ? "" : "s"
                self.membersDetailLabel.text = "\(membersCount) member\(membersSuffix)"

                let hostsCount = self.hosts.count
                let hostsSuffix = hostsCount == 1 ? "" : "s"
                self.hostsDetailLabel.text = "\(hostsCount) pinned public-key\(hostsSuffix)"

            } catch {
                self.showWarning(title: "Error fetching team", body: "\(error)")
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        headerView.layer.shadowColor = UIColor.black.cgColor
        headerView.layer.shadowOffset = CGSize(width: 0, height: 0)
        headerView.layer.shadowOpacity = 0.175
        headerView.layer.shadowRadius = 3
        headerView.layer.masksToBounds = false
        
        fetchTeamUpdates()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    /// KRTeamDataControllerDelegate
    
    var controller: UIViewController {
        return self
    }
    
    func update(identity: TeamIdentity) {
        self.identity = identity
    }
    
    /// Leave Team
    
    @IBAction func leaveTeamTapped() {
        
        var team:Team
        
        do {
            team = try self.identity.team()
        } catch {
            self.showWarning(title: "Error fetching team", body: "\(error)")
            return
        }
        
        let message = "You will no longer have access to the team's data and your team admin will be notified that you are leaving the team. Are you sure you want to continue?"
        
        let sheet = UIAlertController(title: "Do you want to leave the \(team.name) team?", message: message, preferredStyle: .actionSheet)
        
        sheet.addAction(UIAlertAction(title: "Leave Team", style: UIAlertActionStyle.destructive, handler: { (action) in
            self.leaveTeamRequestAuth()
        }))
        
        sheet.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (action) in
        }))
        
        present(sheet, animated: true, completion: nil)

    }
    
    func leaveTeamRequestAuth() {
        authenticate { (yes) in
            guard yes else {
                return
            }
            
            do {
                try IdentityManager.removeTeamIdentity()
            } catch {
                self.showWarning(title: "Error", body: "Cannot leave team: \(error)")
                return
            }
            
            dispatchMain {
                self.performSegue(withIdentifier: "showLeaveTeam", sender: nil)
            }
        }
    }
    
    func authenticate(completion:@escaping (Bool)->Void) {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthentication
        let reason = "Leave the \(self.team?.name ?? "") team?"
        
        var err:NSError?
        guard context.canEvaluatePolicy(policy, error: &err) else {
            log("cannot eval policy: \(err?.localizedDescription ?? "unknown err")", .error)
            completion(true)
            
            return
        }
        
        
        dispatchMain {
            context.evaluatePolicy(policy, localizedReason: reason, reply: { (success, policyErr) in
                completion(success)
            })
        }
        
    }


    /// TableView

    enum Cell:String {
        case hosts = "hosts"
        case activity = "activity"
        case members = "members"
        
        var segue:String {
            switch self {
            case .hosts:
                return "showTeamKnownHosts"
            case .activity:
                return "showTeamActivity"
            case .members:
                return "showTeamMembers"
            }
        }
        
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cellID = tableView.cellForRow(at: indexPath)?.reuseIdentifier,
              let cell = Cell(rawValue: cellID)
        else {
            log("no such cell action id")
            return
        }
        
        self.performSegue(withIdentifier: cell.segue, sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let activityController = segue.destination as? TeamActivityController {
            activityController.blocks = self.blocks
            activityController.identity = self.identity
        } else if let membersController = segue.destination as? TeamMemberListController {
            membersController.members = self.members
            membersController.identity = self.identity
        } else if let hostsController = segue.destination as? TeamKnownHostsController {
            hostsController.hosts = self.hosts
            hostsController.identity = self.identity
        }
    }
}









