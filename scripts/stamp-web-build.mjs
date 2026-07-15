#!/usr/bin/env node
/**
 * Stamp the deployable web build (build/web) with a unique build version.
 *
 * 1. Replaces BUILD_VERSION in build/web/sw.js so every deployment ships a
 *    byte-different service worker with its own cache name. This is what
 *    makes clients drop the previous deployment's cache-first assets
 *    (main.dart.js has no content hash in its filename).
 * 2. Merges version metadata into build/web/version.json, preserving the
 *    snake_case keys Flutter generates (package_info_plus reads
 *    app_name/version/build_number/package_name) and adding the camelCase
 *    keys WebUpdateChecker reads (version/buildNumber/gitSha).
 *
 * Inputs (all optional): APP_VERSION, APP_BUILD_NUMBER, APP_GIT_SHA env vars.
 * Fallbacks: existing version.json values, pubspec.yaml, `git rev-parse HEAD`.
 *
 * Run after `flutter build web` and before deploying. `npm run deploy:web`
 * runs it automatically via the predeploy:web hook.
 */
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webRoot = path.join(repoRoot, 'build', 'web');
const swPath = path.join(webRoot, 'sw.js');
const versionJsonPath = path.join(webRoot, 'version.json');

function fail(message) {
  console.error(`[stamp-web-build] ${message}`);
  process.exit(1);
}

if (!existsSync(swPath)) {
  fail(`${swPath} not found – run "flutter build web" first.`);
}

function resolveGitSha(existing) {
  const fromEnv = (process.env.APP_GIT_SHA ?? '').trim();
  if (fromEnv) return fromEnv;
  // A gitSha already present in version.json means this build/web came from
  // a stamped artifact – keep its sha rather than the deployer's local HEAD.
  // A fresh `flutter build web` regenerates version.json without gitSha.
  const fromExisting = `${existing.gitSha ?? ''}`.trim();
  if (fromExisting && fromExisting !== 'unknown') return fromExisting;
  try {
    return execSync('git rev-parse HEAD', { cwd: repoRoot }).toString().trim();
  } catch {
    return '';
  }
}

function pubspecVersion() {
  try {
    const pubspec = readFileSync(path.join(repoRoot, 'pubspec.yaml'), 'utf8');
    const match = pubspec.match(/^version:\s*(\S+)/m);
    return match ? match[1] : '';
  } catch {
    return '';
  }
}

let existing = {};
try {
  existing = JSON.parse(readFileSync(versionJsonPath, 'utf8'));
} catch {
  // Missing or invalid version.json is fine – we create it below.
}

const [pubspecVer, pubspecBuild] = pubspecVersion().split('+');

const version =
  (process.env.APP_VERSION ?? '').trim() ||
  existing.version ||
  pubspecVer ||
  '0.0.0';
const buildNumber = String(
  (process.env.APP_BUILD_NUMBER ?? '').trim() ||
    existing.build_number ||
    existing.buildNumber ||
    pubspecBuild ||
    '0',
);
const gitSha = (resolveGitSha(existing) || 'unknown').toLowerCase();

// Cache-name suffix: deterministic per deployment when the SHA is known,
// timestamp otherwise so repeated local deploys still bust the cache.
const buildVersion =
  gitSha === 'unknown'
    ? `local-${Date.now()}-${buildNumber}`
    : `${gitSha.slice(0, 12)}-${buildNumber}`;

// ── Stamp sw.js ────────────────────────────────────────────────
const sw = readFileSync(swPath, 'utf8');
const swPattern = /const BUILD_VERSION = '[^']*';/;
if (!swPattern.test(sw)) {
  fail(`${swPath} has no BUILD_VERSION line – web/sw.js format changed?`);
}
writeFileSync(swPath, sw.replace(swPattern, `const BUILD_VERSION = '${buildVersion}';`));

// ── Merge version.json ─────────────────────────────────────────
const merged = {
  ...existing,
  version,
  build_number: buildNumber,
  buildNumber,
  gitSha,
};
writeFileSync(versionJsonPath, `${JSON.stringify(merged, null, 2)}\n`);

console.log(
  `[stamp-web-build] sw.js BUILD_VERSION=${buildVersion}; ` +
    `version.json version=${version} buildNumber=${buildNumber} gitSha=${gitSha}`,
);
