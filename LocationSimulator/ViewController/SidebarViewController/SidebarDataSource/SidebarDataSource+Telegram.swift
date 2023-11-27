//
//  SidebarDataSource+Telegram.swift
//  LocationSimulator
//
//  Created by のの on 24/11/2023.
//  Copyright © 2023 David Klopp. All rights reserved.
//

import Foundation
import AppKit
import CLogger
import LocationSpoofer

class TgItem {
    var name = ""
//    var long = ""
//    var lat = ""
}
extension SidebarDataSource {
    
    
    private func fetchTgData(completion: @escaping ([String]?, Error?) -> Void) {
        print("fetchTgData")
        let url = URL(string: "http://nono.manabb.com/api/telegram/v1/message/mhlocation")!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in

            guard let data = data, error == nil else { return }

             do {
                 // make sure this JSON is in the format we expect
                 // convert data to json
                 if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                     // try to read out a dictionary
//                     print(json)
                     if let data = json["data"] as? [String] {
//                         print(data)
                         completion(data, nil)
                     }
                 }
             } catch let error as NSError {
                 completion(nil, error)
                 print("Failed to load: \(error.localizedDescription)")
             }

         }
//        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
//            guard let data = data else { return }
//            do {
//                if let array = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? TgLocationResult{
//                    print("success", array)
//                    completion(array, nil)
//                }
//            } catch {
//                print("error", error)
//                completion(nil, error)
//            }
//        }
        task.resume()
    }
    public func removeTgLocationRecord() {
        print(self.sidebarView?.numberOfRows ?? "-")
        for (index, _) in self.tgLocations.enumerated().reversed() {
            self.tgLocations.remove(at: index)
            let newIndex = 1 + self.realDevices.count + 1 + self.simDevices.count + 1 + index
            self.sidebarView?.removeItems(at: [newIndex], inParent: nil, withAnimation: .effectFade)
        }
    }
    public func fetchTgLocationRecord() {
        self.fetchTgData { (dict, error) in
            if (dict != nil) {
                DispatchQueue.main.async {
                    self.removeTgLocationRecord()
                    
                    for (index, device) in ((dict ?? []) as [String]).enumerated() {
                        let b = TgItem()
                        b.name = device
                        self.tgLocations.append(b)
                        let newIndex = 1 + self.realDevices.count + 1 + self.simDevices.count + 1 + index
                        self.sidebarView?.insertItems(at: [newIndex], inParent: nil, withAnimation: .effectGap)
                    }
                }
            }
        }
//        let devices = [
//            "22.42087823, 114.22542759",
//            "22.3163426, 114.2082753",
//            "22.34947026,114.177152507" ,
//            "[20:08]22.4037343,113.9826032",
//            "[20:08]22.3089113,114.1667327",
//            "[20:08]22.322835,114.232353",
//            "[20:08]22.361925,114.170823",
//            "[20:08]22.464316,114.179227"
//        ]
////        self.tgLocations.removeAll()
//        for (index, device) in devices.enumerated() {
//            let b = TgItem()
//            b.name = device
//            self.tgLocations.append(b)
//            let newIndex = 1 + self.realDevices.count + 1 + self.simDevices.count + 1 + index
//            self.sidebarView?.insertItems(at: [newIndex], inParent: nil, withAnimation: .effectGap)
//        }
    }
}
