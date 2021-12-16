/*
 *  Constants.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import RediStack

let SOFTWARE_VERSION: String = "2.0.0a (2021.12.15)"
let HEARTBEAT = 10
let HEARTBEAT_TTL = Int(Double(HEARTBEAT) * 1.3)
let XCTVAPOR_KEY: RedisKey = "key:XCTVapor:private"
let XCTVAPOR_USERNAME = "XCTVapor"
