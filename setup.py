#!/usr/bin/env python3

import os
import hashlib

version = "0.1.5"

def salted_md5(input):
	salted = "smoke" + input + "stack"
	md5_hash = hashlib.md5(salted.encode())
	return md5_hash.hexdigest()

print("\nsmokestack-vapor setup v" + version)
print("\nHTTP parameters:")
hostname = input(" 1/8 Enter hostname: ")
port = input(" 2/8 Enter port number: ")
print("\nSecrets:")
pw_app = input(" 3/8 Enter password for iOS app: ")
pw_firmware = input(" 4/8 Enter password for firwmare: ")
pw_insomnia = input(" 5/8 Enter password for Insomnia (or Postman, SoapUI...): ")
pw_xctvapor = input(" 6/8 Enter password for XCTVapor (WARNING: stored in Redis using plaintext!): ")
print("\nAPNS parameters:")
apns_team_id = input(" 7/8 Enter APNS Team ID: ")
apns_key_id = input(" 8/8 Enter APNS Key ID: ")

with open(".env", "w") as env_file:
	env_file.write("HOSTNAME=" + hostname + "\n")
	env_file.write("PORT=" + port + "\n")
	env_file.write("APNS_TEAM_ID=" + apns_team_id + "\n")
	env_file.write("APNS_KEY_ID=" + apns_key_id + "\n")

os.system("redis-cli set key:app {key}".format(key=salted_md5(pw_app)))
os.system("redis-cli set key:firmware {key}".format(key=salted_md5(pw_firmware)))
os.system("redis-cli set key:Insmonia {key}".format(key=salted_md5(pw_insomnia)))
os.system("redis-cli set key:XCTVapor {key}".format(key=salted_md5(pw_xctvapor)))
os.system("redis-cli set key:XCTVapor:private {key}".format(key=pw_xctvapor))

print("Done.\n")

print("*** Please ensure your APNS .p8 certificate is available at /etc/ssl/apns/smokestack.p8 ***\n")
