// Publish the relay to Cloudflare and point the game at it.
//   npx wrangler login     (once: opens a browser to sign in / create a free Cloudflare account)
//   npm run deploy
// Then re-export the game (see README.md) so the .exe uses the new server.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const run = spawnSync('npx', ['wrangler', 'deploy'], { encoding: 'utf8', shell: true, stdio: ['inherit', 'pipe', 'pipe'] });
const out = `${run.stdout ?? ''}\n${run.stderr ?? ''}`;
process.stdout.write(out);
if (run.status !== 0) {
  console.error('\nDeploy failed. If it says you are not logged in, run: npx wrangler login');
  process.exit(run.status ?? 1);
}
const m = out.match(/https:\/\/[a-z0-9.-]+\.workers\.dev/i);
if (!m) {
  console.error('\nDeployed, but the workers.dev address was not in the output. Set Net.DEFAULT_SERVER by hand.');
  process.exit(1);
}
const wss = m[0].replace(/^https:/, 'wss:');
const file = fileURLToPath(new URL('../scripts/net/net_client.gd', import.meta.url));
const src = readFileSync(file, 'utf8');
const next = src.replace(/const DEFAULT_SERVER := "[^"]*"/, `const DEFAULT_SERVER := "${wss}"`);
writeFileSync(file, next);
console.log(`\nThe game now connects to ${wss} (scripts/net/net_client.gd).`);

const test = spawnSync('node', ['test-relay.mjs', wss], { encoding: 'utf8', stdio: 'inherit', cwd: fileURLToPath(new URL('.', import.meta.url)) });
if (test.status !== 0) process.exit(test.status ?? 1);
console.log('\nNext: re-export the game so the .exe uses it (see README.md).');
