//
//  AppDelegate+Notifications.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/21/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UserNotifications

extension AppDelegate {
    
    /// UserNotificationCenterDelegate
    
    // foreground notification
    // The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the handler is not called in a timely manner then the notification will not be presented. The application can choose to have the notification presented as a sound, badge, alert and/or in the notification list. This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Swift.Void) {
        
        log("willPresentNotifcation - Foreground", .warning)
        completionHandler(.sound)
    }
    
    
    // The method will be called on the delegate when the user responded to the notification by opening the application, dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Swift.Void) {

        // user didn't select option, simply opened the app with the notification
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            handleNotification(userInfo: response.notification.request.content.userInfo)
            return
        }
    
        handleAction(userInfo: response.notification.request.content.userInfo, identifier: response.actionIdentifier, completionHandler: completionHandler)
    }
    
    
    
    // MARK: Application remote notification
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Swift.Void) {
        log("didReceieveRemoteNotification", .warning)
        completionHandler(.noData)
    }


    //MARK: Notification Handler Methods
    func handleNotification(userInfo:[AnyHashable : Any]?) {
        if
            let sessionID = userInfo?["session_id"] as? String,
            let session = SessionManager.shared.get(id: sessionID),
            let requestObject = userInfo?["request"] as? [String:Any],
            let request = try? Request(json: requestObject)
            
        {
            // if approval notification
            TransportControl.shared.handle(medium: .remoteNotification, with: request, for: session)
        }
        
    }
    
    
    func handleAction(userInfo:[AnyHashable : Any]?, identifier:String, completionHandler:@escaping ()->Void) {
        
        if let (session, request) = try? convertLocalJSONAction(userInfo: userInfo) {
            handleRequestAction(session: session, request: request, identifier: identifier, completionHandler: completionHandler)
        } else if let (session, request) = try? unsealUntrustedAction(userInfo: userInfo) {
            handleRequestAction(session: session, request: request, identifier: identifier, completionHandler: completionHandler)
        } else {
            log("invalid notification", .error)
            completionHandler()
        }
    }
    
    func unsealUntrustedAction(userInfo:[AnyHashable : Any]?) throws -> (Session,Request) {
        guard let notificationDict = userInfo?["aps"] as? [String:Any],
            let ciphertextB64 = notificationDict["c"] as? String,
            let ciphertext = try? ciphertextB64.fromBase64(),
            let sessionUUID = notificationDict["session_uuid"] as? String,
            let session = SessionManager.shared.get(queue: sessionUUID),
            let alert = notificationDict["alert"] as? String,
            alert == "Kryptonite Request"
            else {
                log("invalid untrusted encrypted notification", .error)
                throw InvalidNotification()
        }
        let sealed = try NetworkMessage(networkData: ciphertext).data
        let request = try Request(from: session.pairing, sealed: sealed)
        return (session, request)
    }
    
    func convertLocalJSONAction(userInfo:[AnyHashable : Any]?) throws -> (Session,Request) {
        guard let sessionID = userInfo?["session_id"] as? String,
            let session = SessionManager.shared.get(id: sessionID),
            let requestObject = userInfo?["request"] as? [String:Any]
            else {
                log("invalid notification", .error)
                throw InvalidNotification()
        }
        return try (session, Request(json: requestObject))
    }
    
    func handleRequestAction(session: Session, request: Request, identifier:String, completionHandler:@escaping ()->Void) {
        // remove pending if exists
        Policy.removePendingAuthorization(session: session, request: request)
        
        guard let actionIdentifier = Policy.ActionIdentifier(rawValue: identifier)
            else {
                log("nil identifier", .error)
                Silo.shared.removePending(request: request, for: session)
                TransportControl.shared.handle(medium: .remoteNotification, with: request, for: session)
                completionHandler()
                return
        }
        
        let signatureAllowed = (identifier == Policy.approveAction.identifier || identifier == Policy.approveTemporaryAction.identifier)
        
        switch actionIdentifier {
        case Policy.ActionIdentifier.approve:
            Policy.set(needsUserApproval: true, for: session) // override setting incase app terminated
            Analytics.postEvent(category: request.body.analyticsCategory, action: "background approve", label: "once")
            
        case Policy.ActionIdentifier.temporary:
            let interval = Policy.temporaryApprovalInterval
            Policy.allow(session: session, for: interval.value)
            Analytics.postEvent(category: request.body.analyticsCategory, action: "background approve", label: "time", value: UInt(interval.value))

        case Policy.ActionIdentifier.reject:
            Policy.set(needsUserApproval: true, for: session) // override setting incase app terminated
            Analytics.postEvent(category: request.body.analyticsCategory, action: "background reject")
            
        }
        
        
        do {
            let resp = try Silo.shared.lockResponseFor(request: request, session: session, signatureAllowed: signatureAllowed)
            try TransportControl.shared.send(resp, for: session, completionHandler: completionHandler)
            
            if let errorMessage = resp.body.error {
                Notify.shared.presentError(message: errorMessage, session: session)
            }
            
        } catch (let e) {
            log("handle error \(e)", .error)
            completionHandler()
            return
        }
    }

}
