//
//  TeamKnownHostsController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/25/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UIKit

class TeamKnownHostsController: KRBaseTableController {
    
    var identity:TeamIdentity!
    var hosts:[SSHHostKey] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()        
        self.title = "Pinned Hosts"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.tableView.reloadData()
    }
    
    /// TableView
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return hosts.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SSHHostKeyCell") as! SSHHostKeyCell
        cell.set(host: hosts[indexPath.row])
        
        return cell
        
    }

}
class SSHHostKeyCell:UITableViewCell {
    @IBOutlet weak var hostLabel:UILabel!
    @IBOutlet weak var keyLabel:UILabel!
    
    func set(host:SSHHostKey) {
        hostLabel.text = host.host
        keyLabel.text = (try? host.publicKey.toAuthorized()) ?? host.publicKey.toBase64()
    }
}
