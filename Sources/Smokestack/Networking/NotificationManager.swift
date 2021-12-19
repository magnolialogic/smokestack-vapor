/*
 *  NotificationManager.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Foundation
import Vapor
import Redis
import APNS
import CoreSmokestack

final class NotificationManager {
	let app: Application
	let apns: APNSController
	let ws: WebSocketController
	private let jsonDecoder = JSONDecoder()
	private let jsonEncoder = JSONEncoder()
	
	init(app: Application) {
		self.app = app
		self.apns = APNSController(app: app)
		self.ws = WebSocketController(app: app)
	}
	
	func send(_ report: SmokeReport) {
		if ws.clients.active.isEmpty {
			let notification = SmokestackAPNSNotification(aps: APNSwiftPayload(hasContentAvailable: true), data: report)
			self.apns.send(notification)
		} else {
			ws.notifyClients(report)
		}
	}
	
	fileprivate func sendReport(environment: Environment, apns: APNSwiftClient, redis: RedisClient, logger: Logger, report: SmokeReport) {
		if ws.clients.active.isEmpty {
			let notification = SmokestackAPNSNotification(aps: APNSwiftPayload(hasContentAvailable: true), data: report)
			self.apns.send(notification)
		} else {
			ws.notifyClients(report)
		}
	}
}

// MARK: - App service

struct NotificationManagerStorageKey: StorageKey {
	typealias Value = NotificationManager
}

extension Application {
	var notificationManager: NotificationManager {
		get {
			self.storage[NotificationManagerStorageKey.self]!
		}
		set {
			self.storage[NotificationManagerStorageKey.self] = newValue
		}
	}
}
