//
//  AppDelegate.swift
//  UniversalWebview
//
//  Created by Mario Kovacevic on 05/08/2016.
//  Copyright (c) 2016 Brommko LLC. All rights reserved.
//

import UIKit
import Firebase
import SwiftyUserDefaults
import SwiftyStoreKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate, OSPermissionObserver, OSSubscriptionObserver {
   
    var window: UIWindow?
    
    var googlePlistExists = false
    let customURLScheme = "superview"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        let urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024, diskPath: nil)
        URLCache.shared = urlCache
        
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            googlePlistExists = true
        }
        
        if #available(iOS 10.0, *) {
            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization( options: authOptions, completionHandler: {_, _ in })
            // For iOS 10 display notification (sent via APNS)
            UNUserNotificationCenter.current().delegate = self
            
            if googlePlistExists == true {
                // For iOS 10 data message (sent via FCM)
                Messaging.messaging().delegate = self
            }
        } else {
            let settings: UIUserNotificationSettings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }
        
        if googlePlistExists == true {
            application.registerForRemoteNotifications()
            FirebaseOptions.defaultOptions()?.deepLinkURLScheme = self.customURLScheme
            FirebaseApp.configure()
        }
        
        let appData = NSDictionary(contentsOfFile: AppDelegate.dataPath())
        if let oneSignalAppID = appData?.value(forKey: "OneSignalAppID") as? String {
            if !oneSignalAppID.isEmpty {
                application.registerForRemoteNotifications()

                let notificationReceivedBlock: OSHandleNotificationReceivedBlock = { notification in
                    print("Received Notification: \(notification!.payload.notificationID)")
                    
                    if let launchURL = notification?.payload.launchURL {
                        print("launchURL = \(String(describing: launchURL))")
                        self.openURL(url: URL(string: launchURL)!)
                    }

                    print("content_available = \(String(describing: notification?.payload.contentAvailable))")
                    
                    if let additionalData = notification?.payload!.additionalData {
                        print("additionalData = \(additionalData)")
                        // DEEP LINK and open url in ViewController WebView
                        // Send notification with Additional Data > example key: "OpenURL" example value: "https://google.com"
                        if let url = additionalData["OpenURL"] as? String {
                            self.openURL(url: URL(string: url)!)
                        }
                    }
                }
                
                let notificationOpenedBlock: OSHandleNotificationActionBlock = { result in
                    // This block gets called when the user reacts to a notification received
                    let payload: OSNotificationPayload? = result?.notification.payload
                    
                    print("Message = \(payload!.body)")
                    print("badge number = \(String(describing: payload?.badge))")
                    print("notification sound = \(String(describing: payload?.sound))")
                    
                    if let additionalData = result!.notification.payload!.additionalData {
                        print("additionalData = \(additionalData)")
                        
                        // DEEP LINK and open url in ViewController WebView
                        // Send notification with Additional Data > example key: "OpenURL" example value: "https://google.com"
                        if let url = additionalData["OpenURL"] as? String {
                            self.openURL(url: URL(string: url)!)
                        }
                        
                        if let actionSelected = payload?.actionButtons {
                            print("actionSelected = \(actionSelected)")
                        }
                        
                        // DEEP LINK from action buttons
                        if let actionID = result?.action.actionID {
                            print("actionID = \(actionID)")
                            if actionID == "id2" {
                                print("do something when button 2 is pressed")
                            } else if actionID == "id1" {
                                print("do something when button 1 is pressed")
                            }
                        }
                    }
                }
                
                let onesignalInitSettings = [kOSSettingsKeyAutoPrompt: false, kOSSettingsKeyInAppLaunchURL: true]
                OneSignal.initWithLaunchOptions(launchOptions, appId: oneSignalAppID, handleNotificationReceived: notificationReceivedBlock, handleNotificationAction: notificationOpenedBlock, settings: onesignalInitSettings)
                OneSignal.inFocusDisplayType = OSNotificationDisplayType.notification
                // Add your AppDelegate as an obsserver
                OneSignal.add(self as OSPermissionObserver)
                OneSignal.add(self as OSSubscriptionObserver)
            }
        } else {
            print("OneSignal API Key is not in the plist file!")
        }
        
        if let productId = appData?.value(forKey: "RemoveAdsPurchaseId") as? String {
            if !productId.isEmpty {
                SwiftyStoreKit.completeTransactions() { completedTransactions in
                    for completedTransaction in completedTransactions {
                        if completedTransaction.transaction.transactionState == .purchased || completedTransaction.transaction.transactionState == .restored {
                            print("purchased: \(completedTransaction.productId)")
                            
                            if completedTransaction.productId == productId {
                                Defaults[.adsPurchased] = true
                            }
                        }
                    }
                }
            }
        }
        
        if let appId = appData?.value(forKey: "AppIDForRateMyApp") as? String {
            if !appId.isEmpty {
                let rate = RateMyApp.sharedInstance
                rate.appID = appId
                rate.trackAppUsage()
            }
        }
        
        return true
    }
    
    func onOSPermissionChanged(_ stateChanges: OSPermissionStateChanges!) {
        // Example of detecting answering the permission prompt
        if stateChanges.from.status == OSNotificationPermission.notDetermined {
            if stateChanges.to.status == OSNotificationPermission.authorized {
                print("Thanks for accepting notifications!")
            } else if stateChanges.to.status == OSNotificationPermission.denied {
                print("Notifications not accepted. You can turn them on later under your iOS settings.")
            }
        }
        // prints out all properties
        print("PermissionStateChanges: \n\(stateChanges)")
    }
    
    func onOSSubscriptionChanged(_ stateChanges: OSSubscriptionStateChanges!) {
        if !stateChanges.from.subscribed && stateChanges.to.subscribed {
            print("Subscribed for OneSignal push notifications!")
        }
        print("SubscriptionStateChange: \n\(stateChanges)")
    }
    
    func messaging(_ messaging: Messaging, didRefreshRegistrationToken fcmToken: String) {
        let refreshedToken:String? = InstanceID.instanceID().token()
        print("FIREBASE TOKEN: \(String(describing: refreshedToken))")
        Messaging.messaging().shouldEstablishDirectChannel = true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // [START openurl]
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any]) -> Bool {
        return application(app, open: url, sourceApplication: nil, annotation: [:])
    }
    
    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        let dynamicLink = DynamicLinks.dynamicLinks()?.dynamicLink(fromCustomSchemeURL: url)
        if let dynamicLink = dynamicLink {
            // Handle the deep link. For example, show the deep-linked content or
            // apply a promotional offer to the user's account.
            // [START_EXCLUDE]
            // In this sample, we just open an alert.
            if #available(iOS 8.0, *) {
                if let url = dynamicLink.url?.absoluteString {
                    self.openURL(url: URL(string: url)!)
                }
            } else {
                // Fallback on earlier versions
            }
            // [END_EXCLUDE]
            return true
        }
        
        // [START_EXCLUDE silent]
        // Show the deep link that the app was called with.
        self.openURL(url: url)
        // [END_EXCLUDE]
        return false
    }
    // [END openurl]
    // [START continueuseractivity]
    @available(iOS 8.0, *)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        guard let dynamicLinks = DynamicLinks.dynamicLinks() else {
            return false
        }
        let handled = dynamicLinks.handleUniversalLink(userActivity.webpageURL!) { (dynamiclink, error) in
            // [START_EXCLUDE]
            self.openURL(url: userActivity.webpageURL!)
            // [END_EXCLUDE]
        }
        
        // [START_EXCLUDE silent]
        if !handled {
            // Show the deep link URL from userActivity.
            if let url = userActivity.webpageURL?.absoluteString {
                self.openURL(url: URL(string: url)!)
            }
        }
        // [END_EXCLUDE]
        return handled
    }
    
    func openURL(url:URL) {
        var urlString = url.absoluteString
        let urlSeperated = urlString.components(separatedBy: "//")
        var parsedURLString:String? = nil
        var host:String = "http"

        if urlSeperated.count > 1 {
            if urlSeperated.count > 2 {
                host = urlSeperated[1]
                urlString = urlSeperated[2]
            } else {
                urlString = urlSeperated[1]
            }
            parsedURLString = "\(host)://\(urlString)"
        } else {
            parsedURLString = "\(host)://\(urlString)"
        }
        
        if parsedURLString != nil {
            UserDefaults.standard.set(parsedURLString, forKey: "URL")
            
            if UIApplication.shared.applicationState == UIApplicationState.background || UIApplication.shared.applicationState == UIApplicationState.inactive {
                
            } else {
                if let window = self.window {
                    if let rootViewController = window.rootViewController {
                        if rootViewController is ViewController {
                            (rootViewController as! ViewController).loadWebView()
                        }
                    }
                }
            }

        }
    }
    
    static func dataPath() -> String {
        return Bundle.main.path(forResource: "SuperView", ofType: "plist")!
    }
}

