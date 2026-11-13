# Toybox Mayhem online relay

The game's online play goes through this small server. It doesn't run the game: one player **hosts** a room (their game runs the match, bots included) and the others **join** with the room code. The relay passes messages between them. It runs on Cloudflare Workers (free plan, no card needed), with one Durable Object per room.

## Put it online (once)

```sh
cd server
npm install
npx wrangler login      # opens a browser: sign in to Cloudflare (or create a free account), click Allow
npm run deploy          # publishes it, writes its address into scripts/net/net_client.gd, tests it
```

Then rebuild the game so it knows the address (from the project folder):

```sh
sh tools/build_installer.sh
```

Share `build/ToyboxMayhem-Setup.exe` with your friends (or attach it to a GitHub release). In the game: **Play online** → one person presses **Host a room** and reads out the code, the others type it and press **Join**.

## Run it on this computer (testing, no account)

```sh
npm run dev                         # ws://127.0.0.1:8787
node test-relay.mjs                 # checks it (or: node test-relay.mjs wss://your-relay.workers.dev)
```

In the game, put `ws://127.0.0.1:8787` in the **Server** box on the Play online screen (leave it empty to use the online server).

## Limits on the free plan

Each player's game sends about 30 messages a second while playing. Cloudflare's free plan allows about 2 million incoming messages a day (100,000 requests, at 20 messages each). That's roughly 10 hours of two-player matches a day, or about 5 hours with four players. Outgoing messages (snapshots to the guests) don't count.
