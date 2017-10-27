//
//  TeamsMarketingController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/24/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UIKit

class TeamsMarketingController:KRBaseController {
    
    @IBOutlet weak var getStartedButton:UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        getStartedButton.layer.shadowColor = UIColor.black.cgColor
        getStartedButton.layer.shadowOffset = CGSize(width: 0, height: 0)
        getStartedButton.layer.shadowOpacity = 0.175
        getStartedButton.layer.shadowRadius = 3
        getStartedButton.layer.masksToBounds = false
    
    }
    
    @IBAction func createTeam() {
        
    }
}

class TeamsCreateController:KRBaseController, UITextFieldDelegate {
    
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var createButton:UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationItem.setKrLogo()

        createButton.layer.shadowColor = UIColor.black.cgColor
        createButton.layer.shadowOffset = CGSize(width: 0, height: 0)
        createButton.layer.shadowOpacity = 0.175
        createButton.layer.shadowRadius = 3
        createButton.layer.masksToBounds = false
        
        nameTextField.isEnabled = true
        
        setCreate(valid: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        nameTextField.becomeFirstResponder()
    }
    
    func setCreate(valid:Bool) {
        
        if valid {
            self.createButton.alpha = 1
            self.createButton.isEnabled = true
        } else {
            self.createButton.alpha = 0.5
            self.createButton.isEnabled = false
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        let text = textField.text ?? ""
        let txtAfterUpdate = (text as NSString).replacingCharacters(in: range, with: string)
        
        setCreate(valid: !txtAfterUpdate.isEmpty)
        
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    @IBAction func createTeam() {
        guard let name = nameTextField.text
            else {
                self.showWarning(title: "Error", body: "Please create a name for your team!", then: {
                    self.dismiss(animated: true, completion: nil)
                })
                return
        }
        
        
        self.performSegue(withIdentifier: "showCreateTeamFromApp", sender: name)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if  let loadController = segue.destination as? TeamLoadController, let name = sender as? String
        {
            loadController.joinType = .createFromApp(name)
        }
    }
    
}
