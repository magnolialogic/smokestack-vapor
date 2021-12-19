/*
 *  Routes.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor

func routes(_ app: Application) throws {
	let protected = app.grouped(UserAuthenticator(), UserAuthenticator.User.guardMiddleware())
	try protected.register(collection: ClientAPICollection())
	try protected.register(collection: SmokerAPICollection())
	try protected.register(collection: StateAPICollection())
	try protected.register(collection: ProgramAPICollection())
	try protected.register(collection: TimerAPICollection())
}
