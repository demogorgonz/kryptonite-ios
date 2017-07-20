//
//  TeamMembersListController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/25/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UIKit

class TeamMemberListController: KRBaseTableController {
    
    var identity:TeamIdentity!
    var members:[Team.MemberIdentity] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.setKrLogo()
        self.title = "Team Members"
    
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return members.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TeamMemberCell") as! TeamMemberCell
        
        let isAdmin = (try? identity.dataManager.isAdmin(for: members[indexPath.row].publicKey)) ?? false
        cell.set(index: indexPath.row, member: members[indexPath.row], isAdmin: isAdmin)
        
        return cell
    }
}

class TeamMemberCell:UITableViewCell {
    @IBOutlet weak var email:UILabel!
    @IBOutlet weak var indexLabel:UILabel!

    func set(index:Int, member:Team.MemberIdentity, isAdmin:Bool = false) {
        indexLabel.text = "\(index+1)."
        
        if isAdmin {
            email.text = member.email + " (owner)"
        } else {
            email.text = member.email
        }
    }
}
