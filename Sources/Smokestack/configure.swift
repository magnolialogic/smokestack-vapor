/*
 *  Configure.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import Redis
import APNS
import JWTKit
import CoreSmokestack

public func configure(_ app: Application) throws {
	app.logger.logLevel = .info
	
	// HTTP Configuration
	app.http.server.configuration.serverName = "smokestack"
	app.http.server.configuration.hostname = Environment.get("HOSTNAME")!
	app.http.server.configuration.port = Int(Environment.get("PORT")!)!
	
	// Redis Configuration
#if os(Linux)
	app.redis.configuration = try RedisConfiguration(hostname: "172.17.0.1") // docker0 interface
#else
	app.redis.configuration = try RedisConfiguration(hostname: "localhost")
#endif
	
	// APNS Configuration
	let jwtAuthConfiguration = APNSwiftConfiguration.AuthenticationMethod.jwt(
		key: try .private(filePath: "/etc/ssl/apns/smokestack.p8"),
		keyIdentifier: JWKIdentifier(string: Environment.get("APNS_KEY_ID")!),
		teamIdentifier: Environment.get("APNS_TEAM_ID")!)
	
	let apnsConfiguration = APNSwiftConfiguration(
		authenticationMethod: jwtAuthConfiguration,
		topic: "net.magnolialogic.smokestack",
		environment: app.environment.name == "production" ? .production : .sandbox,
		logger: app.logger)
	
	app.apns.configuration = apnsConfiguration
	
	
	
	// Fire it up!
	try routes(app)
	try app.boot()
	
	// Nuke any stale keys left over by an unclean exit
	_ = app.redis.delete(["online", "state", "program", "version:firmware"])
	
	// Register for Redis expire keyevent notifications for "online" to send APNS + clean up other keys
	_ = app.redis.subscribe(to: "__keyevent@0__:expired") { (publisher, message) in
		if message.description == "online" {
			app.logger.info("Smoker.heartbeat(): offline, smoker missed heartbeat window")
			let statePatch = SmokeState.PatchContent(online: false)
			let report = SmokeReport(statePatch: statePatch)
			NotificationManager.shared.send(report, for: app)
			_ = app.redis.delete(["state", "version:firwmare"])
		}
	}
	
	// Wake-up call for any clients waiting for a connection
	if app.environment != .testing {
		NotificationManager.shared.send(SmokeReport(softwareVersion: SOFTWARE_VERSION), for: app)
	}
}
