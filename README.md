# vapor-smokestack

Vapor/Swift backend for [smokestack](https://magnolialogic.github.io/smokestack). Build/test locally on macOS or deploy to Ubuntu using docker-compose.


#### Prerequisites
* Docker + docker-compose
* Redis running on port 6379 with protected-mode off (edit /etc/redis/redis.conf)
* HTTP server + proxy (e.g. nginx) with SSL configured

#### Installation
1. Clone repo into /opt/
2. `cd /opt/smokestack-vapor`
3. `python3 setup.py`
4. `docker-compose up`

### Routes
`/api/client`<br>
GET: Basic Auth endpoint for iOS app, stores APNS device token and responds with Vapor version<br>
DELETE: Removes device token from APNS pool

`/api/client/password`<br>
POST: Changes Basic Auth password

`/api/client/ws`<br>
GET: Upgrades connection / create WebSocket

`/api/smoker/boot`<br>
POST: Called on boot by smoker firmware, nukes any stale keys, initializes state, and stores firmware version

`/api/smoker/heartbeat`<br>
POST: Called by smoker every 10 seconds to update latest state, temperatures, and check for any pending interrupts from iOS app

`/api/smoker/power`<br>
POST: Called by iOS app to direct smoker to run its current program
DELETE: Called by iOS app to force smoker shutdown

`/api/smoker/target`<br>
PATCH: Called by iOS app to specify target temperature for grill, probe, or both

`/api/state`<br>
GET: Fetches current SmokeState as JSON
PUT: Full replacement of current state in Redis DB
PATCH: Update specified SmokeState properties

`/api/program`<br>
GET: Returns UUID of current program, if it exists
POST: Called by iOS app to create a new program
DELETE: Called by iOS app or when smoker firmware enters Shutdown mode

`/api/program/:id`<br>
GET: Returns [SmokeStep] for program with specified UUID

`/api/program/index`<br>
GET: Returns index indicating which program step is active
POST: Called by firmware when changing programs

`/api/timer/program/started`<br>
GET: Returns timestamp for last program change
POST: Called by firmware when changing programs
DELETE: Deletes "program started" timer
