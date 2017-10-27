//
//  ViewController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 8/26/16.
//  Copyright © 2016 KryptCo, Inc. Inc. All rights reserved.
//

import UIKit

class MainController: UITabBarController, UITabBarControllerDelegate {

    var blurView = UIVisualEffectView(effect: UIBlurEffect(style: UIBlurEffectStyle.light))
    
    lazy var aboutButton:UIBarButtonItem = {
        return UIBarButtonItem(image: UIImage(named: "gear"), style: UIBarButtonItemStyle.plain, target: self, action: #selector(MainController.aboutTapped))
    }() 
    
    lazy var helpButton:UIBarButtonItem = {
        return UIBarButtonItem(title: "Help", style: UIBarButtonItemStyle.plain, target: self, action: #selector(MainController.helpTapped))
    }()
    
    enum TabIndex:Int {
        case me = 0
        case pair = 1
        case devices = 2
        case teams = 3
        
        var index:Int { return rawValue }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.setKrLogo()
                
        self.tabBar.tintColor = UIColor.app
        self.delegate = self
        
        // add a blur view
        view.addSubview(blurView)
                
        self.navigationItem.leftBarButtonItem = aboutButton
        self.navigationItem.rightBarButtonItem = helpButton
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        blurView.frame = view.frame

        if !KeyManager.hasKey() {
            self.blurView.isHidden = false
        }
        
        // set the right 4th tab if needed
        updateTeamTabIfNeeded()
        
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard KeyManager.hasKey() else {
            self.performSegue(withIdentifier: "showOnboardGenerate", sender: nil)
            return
        }
        
        guard  let _ = try? IdentityManager.getMe()
        else {
            self.performSegue(withIdentifier: "showOnboardEmail", sender: nil)
            return
        }
        
        guard Onboarding.isActive == false else {
            self.performSegue(withIdentifier: "showOnboardFirstPair", sender: nil)
            return
        }
        
        UIView.animate(withDuration: 0.2, animations: {
            self.blurView.isHidden = true
        })
        
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "load_new_me"), object: nil)

        
        // Check old version sessions
        let (hasOld, sessionNames) = SessionManager.hasOldSessions()
        if hasOld {
            self.performSegue(withIdentifier: "showRePairWarning", sender: sessionNames)
            return
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    @IBAction func dismissOnboarding(segue: UIStoryboardSegue) {
        Onboarding.isActive = false
    }
    

    @IBAction func dismissHelpAndGoToPair(segue: UIStoryboardSegue) {
        self.selectedIndex = TabIndex.pair.index
    }
    
    
    var shouldSwitchToTeams:Bool = false
    @IBAction func dismissJoinTeam(segue: UIStoryboardSegue) {
        updateTeamTabIfNeeded()
        self.selectedIndex = TabIndex.teams.index
    }
    
    @IBAction func didDeleteTeam(segue: UIStoryboardSegue) {
        updateTeamTabIfNeeded()
        self.selectedIndex = TabIndex.me.index
    }

    
    //MARK: Nav Bar Buttons
    
    @objc dynamic func aboutTapped() {
        self.performSegue(withIdentifier: "showAbout", sender: nil)
    }
    
    @objc dynamic func helpTapped() {
        self.performSegue(withIdentifier: "showInstall", sender: nil)
    }
    
    //MARK: Teams tab
    
    func updateTeamTabIfNeeded() {
        
        // load the identients
        var teamIdentity:TeamIdentity?
        var team:Team?
        
        do {
            teamIdentity = try IdentityManager.getTeamIdentity()
            team = try teamIdentity?.team()
        } catch {
            log("error loading team: \(error)", .error)
            return
        }
        
        
        switch teamIdentity {
        case .some(let identity): // team detail controller
            let controller = Resources.Storyboard.Team.instantiateViewController(withIdentifier: "TeamDetailController") as! TeamDetailController
            controller.identity = identity
            let tabBarItem = UITabBarItem(title: team?.name ?? "Team", image: #imageLiteral(resourceName: "teams"), selectedImage: #imageLiteral(resourceName: "teams_selected"))
            
            let controllers = viewControllers?[0 ..< TabIndex.teams.index] ?? []
            self.setViewControllers([UIViewController](controllers + [controller]), animated: true)
            controller.tabBarItem = tabBarItem
            
            if shouldSwitchToTeams {
                self.selectedIndex = TabIndex.teams.index
                shouldSwitchToTeams = false
            }

            
        case .none: // marketing controller
            self.selectedIndex = TabIndex.me.index
            
            let marketingController = Resources.Storyboard.Team.instantiateViewController(withIdentifier: "TeamsMarketingController") as! TeamsMarketingController
            let tabBarItem = UITabBarItem(title: "Teams", image: #imageLiteral(resourceName: "teams"), selectedImage: #imageLiteral(resourceName: "teams_selected"))
            
            let controllers = viewControllers?[0 ..< TabIndex.teams.index] ?? []
            self.setViewControllers([UIViewController](controllers + [marketingController]), animated: true)
            marketingController.tabBarItem = tabBarItem
        }
    }
    
    
    //MARK: Prepare for segue
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if  let rePairWarningController = segue.destination as? RePairWarningController,
            let sessionNames = sender as? [String]
        {
            rePairWarningController.names = sessionNames
        }
    }

}
