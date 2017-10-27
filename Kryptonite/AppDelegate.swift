//
//  AppDelegate.swift
//  Kryptonite
//
//  Created by Alex Grinman on 8/26/16.
//  Copyright © 2016 KryptCo, Inc. Inc. All rights reserved.
//

//

import UIKit
import UserNotifications

struct InvalidNotification:Error{}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    var pendingLink:Link?
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {


        Analytics.migrateOldIDIfExists()
        Analytics.migrateAnalyticsDisabled()
                
        Resources.makeAppearences()
        
        if !API.provision() {
            log("API provision failed.", LogType.error)
        }
        
        AWSLogger.default().logLevel = .none
        TransportControl.shared.add(sessions: SessionManager.shared.all)
                
        // check for link
        if  let url = launchOptions?[UIApplicationLaunchOptionsKey.url] as? URL,
            let link = try? Link(url: url)
        {
            pendingLink = link
        }
        
        UNUserNotificationCenter.current().delegate = self

        //Weird behavior when we don't re-register?
        if application.isRegisteredForRemoteNotifications {
            self.registerPushNotifications()
        }

        Analytics.appLaunch()
        

        return true
    }
    
    
    //MARK: Registering Notifications
    func registerPushNotifications() {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().setNotificationCategories([Policy.authorizeCategory])
            UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { (success, error) in
                if let err = error {
                    log("got error requesting push notifications: \(err)", .error)
                    return
                }
                
                log("registered for push: \(success)")
                dispatchMain {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            })
        }
    }
    
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let chars = deviceToken.bytes
        var token = ""
        
        for i in 0..<deviceToken.count {
            token += String(format: "%02.2hhx", arguments: [chars[i]])
        }
        
        log("Got token: \(token)")
        
        API().updateSNS(token: token) { (endpoint, err) in
            guard let arn = endpoint else {
                log("AWS SNS error: \(String(describing: err))", .error)
                return
            }
            
            do {
                try KeychainStorage().set(key: Constants.endpointARNStorageKey, value: arn)
            } catch {
                log("Could not save push ARN", .error)
            }
            
            API().setEndpointEnabledSNS(endpointArn: arn, completionHandler: { (err) in
                if let err = err {
                    log("AWS SNS endpoint enable error: \(err)", .error)
                    return
                }
            })
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        
        log("Push registration failed!", .error)
    }
    
    //MARK: Links
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        
        do {
            self.pendingLink = try Link(url: url)
            NotificationCenter.default.post(name: Link.notificationName, object: self.pendingLink, userInfo: nil)
            return true
        } catch {
            log("invalid link: \(url.absoluteString)", .error)
            return false
        }
    }
    
    //MARK: Update Checking in the Background
    
    func checkForAppUpdateIfNeededBackground() {
        Updater.checkForUpdateIfNeeded { (version) in
            guard let newVersion = version else {
                log("no new version found")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "New Version Available"
            content.body = "Kryptonite (v\(newVersion.string)) is now available. Please update at your earliest convenience."
            content.sound = UNNotificationSound.default()
            
            let request = UNNotificationRequest(identifier: "update", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }

    }
   
    //MARK: App Lifecycle
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        TransportControl.shared.willEnterBackground()
        Analytics.appClose()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        
        TransportControl.shared.willEnterForeground()
        
        application.applicationIconBadgeNumber = 1
        application.applicationIconBadgeNumber = 0
        Analytics.setUserAgent()
        Analytics.appOpen()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        
        if let pending = Policy.lastPendingAuthorization {
            log("requesting pending authorization")
            Policy.requestUserAuthorization(session: pending.session, request: pending.request)
        }

        // if team policy set: refresh approval category on notifications
        if  let team = (try? IdentityManager.getTeamIdentity()?.team()) as? Team,
            let _ = team.policy.temporaryApprovalSeconds
        {
            self.registerPushNotifications()
        }
 
        
        //  Send email again if not sent succesfully
        if let email = try? IdentityManager.getMe() {
            dispatchAsync { Analytics.sendEmailToTeamsIfNeeded(email: email) }
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        TransportControl.shared.willEnterBackground()
    }


}

