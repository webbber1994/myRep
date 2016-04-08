//
//  Const.swift
//  BabyMonitor
//
//  Created by dede on 4/3/16.
//  Copyright © 2016 dede. All rights reserved.
//

class Const {


    static let IMG_MSG =  1;
    static let LEN_MSG  = 2;
    static let WARNING_MSG = 3;

    static let READ_TIMEOUT = 15.0;
    static let READ_TIMEOUT_EXTENSION = 10.0;
}

enum AVCamSetupResult : Int {
    case Success
    case CameraNotAuthorized
    case SessionConfigurationFailed
}
