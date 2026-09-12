# Deploy and Host Spoolman on Railway

Spoolman keeps track of your 3D-printer filament: which spools you own, what material and colour
each one is, who made it, and how many grams are left. Your printer talks to it directly, so every
print subtracts what it used and the numbers stay honest without you weighing anything. Klipper
through Moonraker, OctoPrint, Home Assistant and several slicers all integrate with it. This is a
community-maintained template; it is not affiliated with the Spoolman project.

## About Hosting Spoolman

Spoolman is small and simple to host: one Python service, one SQLite database, one directory holding
the database and its nightly backups. There is no companion database and no queue, so a deployment
is a single service with a single persistent volume.

The part that needs care is authentication, because Spoolman has none. Upstream says so directly in
its source: the boundary that protects a user's data is the network. That is a sound assumption on a
home network and a dangerous one on a hosting platform, where every service is handed a public
address the moment it starts. Deployed as-is, anyone who finds the URL can read your inventory,
change it, or delete it. This template puts a password in front of the application and binds the
application itself to loopback, so the only way in is through the front door. The password is
generated for you, and printer integrations still work because they authenticate through the URL.

## Why Deploy Spoolman on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Spoolman on Railway, you are one step closer to supporting a complete full-stack
application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

Concretely, this template attaches the volume and fixes its ownership, generates the password,
configures the front door, pins the listening port to the generated domain, and points the
healthcheck at the one route that stays open, so you get a working and protected instance with
nothing to fill in.

## Common Use Cases

- Check from your phone whether you have enough filament left before starting a long print.
- Let several printers report their usage into one inventory that stays correct on its own.
- Keep a record of what each spool cost and which vendor it came from, so reordering is not guesswork.
- Share one inventory across a workshop, a makerspace or a household without putting it on the open
  internet.

## Dependencies for Spoolman Hosting

- A persistent volume for the SQLite database and its backups.
- A printer or slicer that speaks the Spoolman API, if you want usage tracked automatically.
- Nothing else. No external database, cache or queue.

### Deployment Dependencies

- Spoolman upstream project and documentation: https://github.com/Donkie/Spoolman
- Caddy, used as the authenticating front door: https://caddyserver.com
- Template repository, wrapper image and tests: https://github.com/youssefsiam38/spoolman-railway
- Published image: `ghcr.io/youssefsiam38/spoolman-railway`
- Spoolman is MIT licensed and Caddy is Apache-2.0; both are permissive.

### Implementation Details

The wrapper adds no application code. It validates the configuration, refuses the settings that
would take the password off, takes ownership of the volume for the user the application runs as,
hashes the password into a proxy configuration it validates before use, waits for the application to
report healthy, and only then opens the public port. Both processes are supervised, so if either
stops the container stops and the platform restarts it.
