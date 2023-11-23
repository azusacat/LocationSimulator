//
//  LSApplication+AppleScript.swift
//  LocationSimulator
//
//  Created by David Klopp on 06.05.22.
//  Copyright © 2022 David Klopp. All rights reserved.
//

import Foundation

/// Extension to the main Application class to support apple script.
extension Application {
    @objc private var devices: [ASDevice] {
        return ASDevice.availableDevices
    }

    @objc private var gpxFiles: [ASGPXFile] {
        return ASGPXFile.openFiles
    }

    @objc private var storages: [ASStorage] {
        return ASStorage.openStorages
    }
}
