//
//  AppDelegate.swift
//  BarberDriver
//
//  Created by Devang Lakhani  on 4/15/21.
//  Copyright © 2021 Devang Lakhani. All rights reserved.
//

import UIKit
import CoreData
import Firebase
import Alamofire
import Reachability


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    var tabBarLoaded:((_ isLoaded: Bool)->())?
    let network = NetworkManager.sharedInstance
   
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Thread.sleep(forTimeInterval: 2.0)
        FirebaseApp.configure()
        IQKeyboardManager.shared.enable = true
        self.registerPushNotification()
        try? network.reachability.startNotifier()
        switch network.reachability.connection {
        case .unavailable:
            let nav = self.window?.rootViewController as! UINavigationController
            let noInternet = UIStoryboard.init(name: "Entry", bundle: nil).instantiateViewController(withIdentifier: "NoInternetVC") as! NoInternetVC
            noInternet.internetStatus = .error
            nav.viewControllers = [noInternet]
        default:
            break
        }
        
    
        // Check for internet
        if !KPWebCall.call.isInternetAvailable(){
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1, execute: {
                KPWebCall.call.networkManager.listener?(NetworkReachabilityManager.NetworkReachabilityStatus.notReachable)
            })
        }
        
        if isOnBoardingOver(){
            navigateUserToHome()
        }
        
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        if let _ = self.getAuthorizationToken() {
            if SocketManager.shared.socket.status != .connected {
                SocketManager.shared.connectSockect()
            }
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        self.saveContext()
        if SocketManager.shared.socket.status == .connected {
            SocketManager.shared.disConnect()
        }
    }
    
    // MARK: - Core Data stack
    
    var managedObjectContext: NSManagedObjectContext{
        return persistentContainer.viewContext
    }
    
    lazy var persistentContainer: NSPersistentContainer = {
        
        let container = NSPersistentContainer(name: "BarberDriver")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()
    
    // MARK: - Core Data Saving support
    
    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}

extension AppDelegate{
    
    // Check user is already logged in or not.
    func checkForUser() -> Bool {
        let users = Driver.fetchDataFromEntity(predicate: nil, sortDescs: nil)
        if !users.isEmpty && getAuthorizationToken() != nil {
            _user = users.first!
            return true
        } else {
            return false
        }
    }
    
    // Check user is already logged in or not.
    func navigateUserToHome() {
        let nav = window?.rootViewController as! UINavigationController
        let loginVC = UIStoryboard.init(name: "Entry", bundle: nil).instantiateViewController(withIdentifier: "LoginVC")
        let serviceVC = UIStoryboard.init(name: "Entry", bundle: nil).instantiateViewController(withIdentifier: "SelectServicesVC")
        let slotVC = UIStoryboard.init(name: "Entry", bundle: nil).instantiateViewController(withIdentifier: "SlotBookingVC")
        let radiusVC = UIStoryboard.init(name: "Entry", bundle: nil).instantiateViewController(withIdentifier: "RadiusVC")
        let homeCont = UIStoryboard.init(name: "Entry", bundle: nil).instantiateViewController(withIdentifier: "JTabBarController")
        if checkForUser() {
            self.registerPushNotification()
            KPWebCall.call.setAccesTokenToHeader(token: _appDelegator.getAuthorizationToken()!)
            SocketManager.shared.connectSockect()
            if !_user.isServiceAdded{
                nav.viewControllers = [loginVC,serviceVC]
            }else if !_user.isAvailblity{
                nav.viewControllers = [loginVC,slotVC]
            }else if _user.maxRadius == "" || _user.minRadius == ""{
                nav.viewControllers = [loginVC,radiusVC]
            }else{
                nav.viewControllers = [loginVC,homeCont]
            }
        } else {
            nav.viewControllers = [loginVC]
        }
        _appDelegator.window?.rootViewController = nav
    }
    
    func removeAllNotification() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    func unregisterForNormalNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
    
    func removeUserInfoAndNavToLogin() {
        removeAuthorizationToken()
        removeFCMToken()
        removeWelcomeToken()
        KPWebCall.call.removeAccessTokenFromHeader()
        SocketManager.shared.disConnect()
        unregisterForNormalNotifications()
        removeAllNotification()
        deleteUserObject()
        if let nav = window?.rootViewController as? UINavigationController{
            _ = nav.popToRootViewController(animated: true)
        }
    }
    
    func deleteUserObject() {
        _userDefault.removeObject(forKey: "availablity")
        _userDefault.synchronize()
        _user = nil
        let users = Driver.fetchDataFromEntity(predicate: nil, sortDescs: nil)
        for user in users{
            managedObjectContext.delete(user)
        }
        saveContext()
    }
    
    func storeAuthorizationToken(strToken: String) {
        _userDefault.set(strToken, forKey: FadeAuthTokenKey)
        _userDefault.synchronize()
    }
    
    func getAuthorizationToken() -> String? {
        return _userDefault.value(forKey: FadeAuthTokenKey) as? String
    }
    
    func removeAuthorizationToken() {
        _userDefault.removeObject(forKey: FadeAuthTokenKey)
        _userDefault.synchronize()
    }
    
    func setOnBoardingStatus(value: Bool) {
        _userDefault.set(value, forKey: FadeOnboardigKey)
        _userDefault.synchronize()
    }
    
    func isOnBoardingOver() -> Bool {
        return _userDefault.value(forKey: FadeOnboardigKey) as? Bool ?? false
    }
    
    
    func setWelcomeStatus(value: Bool) {
        _userDefault.set(value, forKey: FadeWelcomeKey)
        _userDefault.synchronize()
    }
    
    func isWelcomeOver() -> Bool {
        return _userDefault.value(forKey: FadeWelcomeKey) as? Bool ?? false
    }
    
    func removeWelcomeToken() {
        _userDefault.removeObject(forKey: FadeWelcomeKey)
        _userDefault.synchronize()
    }
    
    func storeFCMToken(token: String) {
        _userDefault.set(token, forKey: FadeFCMTokenKey)
        _userDefault.synchronize()
    }
    
    func getFCMToken() -> String {
        return _userDefault.value(forKey: FadeFCMTokenKey) as? String ?? ""
    }
    
    func removeFCMToken() {
        _userDefault.removeObject(forKey: FadeFCMTokenKey)
        _userDefault.synchronize()
    }
    
    func storeAppVersion(version: String) {
        _userDefault.set(version, forKey: FadeAppUpdateKey)
        _userDefault.synchronize()
    }
    
    func getAppVersionFromServer() -> String {
        return _userDefault.value(forKey: FadeAppUpdateKey) as? String ?? ""
    }
}

extension AppDelegate{
    
    func getTabBarVC() -> JTabBarController? {
        var tabBar: JTabBarController? = nil
        let nav = _appDelegator.window?.rootViewController as! KPNavigationViewController
        for vc in nav.viewControllers{
            if let tab = vc as? JTabBarController {
                if tab.isViewLoaded{
                    tabBar = tab
                }
                break
            }
        }
        return tabBar
    }
    func navigateUserForPush(noti: NotificationList) {
        self.tabBarLoaded = { (isLoaded) -> () in
            JPUtility.shared.performOperation(0.3) {
                DispatchQueue.main.async {
                    self.redirectToUI(noti: noti)
                }
            }
        }
        self.redirectToUI(noti: noti)
    }
    
    func redirectToUI(noti: NotificationList) {
        if let tabBar = getTabBarVC() {
            tabBarLoaded = nil
            tabBar.selectedIndex = 0
            tabBar.tabBarView.selectedIndexTintColor(index: 0)
            if let home = tabBar.viewControllers![0] as? NearByVC {
                home.navToNotification()
            }
        }
    }
}



// MARK: - Push notification.
extension AppDelegate: UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func registerPushNotification() {
        UNUserNotificationCenter.current().delegate = self
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions, completionHandler: { (granted, error) in
            kprint(items: "Notification Acccess: \(granted)")
        })
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Swift.Void){
        let info = notification.request.content.userInfo
        kprint(items: ">> Payload << :\(info)")
        if let nav = window?.rootViewController as? UINavigationController {
            if let currOpenVC = nav.children.last {
                if currOpenVC != MessagesListVC() {
                    completionHandler([.alert, .badge, .sound])
                }
            }
        }
        completionHandler([.alert, .badge, .sound])
    }
    //Missed call
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        kprint(items: ">> Payload << :\(info)")
        
       /* let noti = NotificationList(dict: info as NSDictionary)
        self.navigateUserForPush(noti: noti) */
        let vc = UIStoryboard(name: "BookingDetails", bundle: nil).instantiateViewController(withIdentifier: "BookingDetailsVC") as! BookingDetailsVC
        let tabBarController = self.window?.rootViewController as? UITabBarController
        if let navController = tabBarController?.selectedViewController as? UINavigationController {
            navController.pushViewController(vc, animated: true)
        }
        completionHandler()
        
        completionHandler()
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let deviceTokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
        // APPLE DEVICE TOCKEN
        NSLog("DEVICE TOKEN:- %@",deviceTokenString)
        let firebaseAuth = Auth.auth()
        firebaseAuth.setAPNSToken(deviceToken, type: AuthAPNSTokenType.prod)

        Messaging.messaging().delegate = self
        Messaging.messaging().token { (token, error) in
            if let error = error {
                print("Error fetching FCM registration token: \(error)")
            } else if let token = token {
                print("FCM registration token: \(token)")
                _appDelegator.storeFCMToken(token: token)
            }
        }

        Messaging.messaging().apnsToken = deviceToken
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            kprint(items: "FCM Token is \(token)")
            _appDelegator.storeFCMToken(token: token)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        kprint(items: error.localizedDescription)
    }
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification notification: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(UIBackgroundFetchResult.noData)
    }
}
