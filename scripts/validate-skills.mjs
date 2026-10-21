#!/usr/bin/env node
/**
 * Validate this repository against the Agent Skills conventions.
 *
 * Checks every skills/<name>/SKILL.md, its frontmatter, the files it references,
 * executable scripts, and that .claude-plugin/marketplace.json stays in sync.
 *
 * Usage: node scripts/validate-skills.mjs
 * Exit:  0 = all checks passed, 1 = at least one error.
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS_DIR = join(ROOT, "skills");
const MARKETPLACE = join(ROOT, ".claude-plugin", "marketplace.json");

const errors = [];
const warnings = [];
const fail = (msg) => errors.push(msg);
const warn = (msg) => warnings.push(msg);

/** Split a SKILL.md into its YAML frontmatter map and markdown body. */
function parseFrontmatter(text) {
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!match) return null;

  const fields = {};
  for (const line of match[1].split(/\r?\n/)) {
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    const at = line.indexOf(":");
    if (at === -1) continue;
    const key = line.slice(0, at).trim();
    let value = line.slice(at + 1).trim();
    // Strip one layer of matching quotes.
    if (/^".*"$/.test(value) || /^'.*'$/.test(value)) value = value.slice(1, -1);
    fields[key] = value;
  }
  return { fields, body: match[2] };
}

const isKebab = (s) => /^[a-z0-9]+(-[a-z0-9]+)*$/.test(s);

/** Collect local paths a SKILL.md points at, e.g. `scripts/foo.sh`. */
function referencedPaths(body) {
  const found = new Set();
  const pattern = /`((?:references|scripts|assets)\/[^`\s]+)`/g;
  for (const match of body.matchAll(pattern)) found.add(match[1].replace(/[.,;:]$/, ""));
  return [...found];
}

function validateSkill(dirName) {
  const dir = join(SKILLS_DIR, dirName);
  const skillFile = join(dir, "SKILL.md");

  if (!statSync(dir).isDirectory()) return;
  if (!existsSync(skillFile)) {
    fail(`${dirName}: missing SKILL.md`);
    return;
  }

  const text = readFileSync(skillFile, "utf8");
  const parsed = parseFrontmatter(text);
  if (!parsed) {
    fail(`${dirName}: SKILL.md must start with --- frontmatter ---`);
    return;
  }

  const { fields, body } = parsed;

  if (!fields.name) fail(`${dirName}: frontmatter missing "name"`);
  if (!fields.description) fail(`${dirName}: frontmatter missing "description"`);

  if (fields.name && fields.name !== dirName) {
    fail(`${dirName}: frontmatter name "${fields.name}" must match the directory name`);
  }
  if (fields.name && !isKebab(fields.name)) {
    fail(`${dirName}: name "${fields.name}" must be lowercase kebab-case`);
  }

  if (fields.description) {
    const desc = fields.description;
    const len = [...desc].length;
    if (len < 40) fail(`${dirName}: description is too short (${len} chars) to trigger reliably`);
    if (len > 1024) fail(`${dirName}: description exceeds 1024 chars (${len})`);
    if (!/use (when|this|for)|should be used when/i.test(desc)) {
      warn(`${dirName}: description has no "Use when..." trigger clause`);
    }
  }

  const words = body.trim().split(/\s+/).filter(Boolean).length;
  if (words < 50) fail(`${dirName}: SKILL.md body is only ${words} words`);
  if (words > 5000) warn(`${dirName}: SKILL.md body is ${words} words; move detail into references/`);

  for (const ref of referencedPaths(body)) {
    if (!existsSync(join(dir, ref))) fail(`${dirName}: SKILL.md references missing file "${ref}"`);
  }

  // Scripts that ship with a skill must be executable and start with a shebang.
  const scriptsDir = join(dir, "scripts");
  if (existsSync(scriptsDir)) {
    for (const entry of readdirSync(scriptsDir)) {
      const path = join(scriptsDir, entry);
      if (!statSync(path).isFile()) continue;
      const head = readFileSync(path, "utf8").split(/\r?\n/, 1)[0];
      if (!head.startsWith("#!")) {
        warn(`${dirName}: scripts/${entry} has no shebang`);
        continue;
      }
      if (!(statSync(path).mode & 0o111)) {
        fail(`${dirName}: scripts/${entry} is not executable (chmod +x)`);
      }
    }
  }
}

function validateMarketplace(skillNames) {
  if (!existsSync(MARKETPLACE)) {
    fail(".claude-plugin/marketplace.json is missing");
    return;
  }

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(MARKETPLACE, "utf8"));
  } catch (error) {
    fail(`.claude-plugin/marketplace.json is not valid JSON: ${error.message}`);
    return;
  }

  if (!manifest.name) fail("marketplace.json: missing name");
  if (!Array.isArray(manifest.plugins) || manifest.plugins.length === 0) {
    fail("marketplace.json: plugins must be a non-empty array");
    return;
  }

  const listed = new Set();
  for (const plugin of manifest.plugins) {
    if (!plugin.name) fail("marketplace.json: a plugin entry has no name");

    const declared = plugin.skills ?? [];
    if (!Array.isArray(declared)) {
      fail(`marketplace.json: plugin "${plugin.name}" skills must be an array`);
      continue;
    }
    if (declared.length === 0) {
      fail(`marketplace.json: plugin "${plugin.name}" lists no skills`);
    }

    for (const entry of declared) {
      const target = join(ROOT, entry);
      if (!existsSync(join(target, "SKILL.md"))) {
        fail(`marketplace.json: plugin "${plugin.name}" points at "${entry}", which has no SKILL.md`);
        continue;
      }
      listed.add(relative(SKILLS_DIR, target));
    }
  }

  for (const name of skillNames) {
    if (!listed.has(name)) fail(`marketplace.json: skill "${name}" is not listed in any plugin`);
  }
  for (const name of listed) {
    if (!skillNames.includes(name)) fail(`marketplace.json: lists "${name}", which does not exist`);
  }
}

// --- run ---

if (!existsSync(SKILLS_DIR)) {
  console.error("No skills/ directory found.");
  process.exit(1);
}

const skillNames = readdirSync(SKILLS_DIR).filter((entry) => {
  const path = join(SKILLS_DIR, entry);
  return statSync(path).isDirectory() && !entry.startsWith(".");
});

if (skillNames.length === 0) fail("skills/ contains no skill directories");

for (const name of skillNames) validateSkill(name);
validateMarketplace(skillNames);

for (const message of warnings) console.warn(`warn  ${message}`);
for (const message of errors) console.error(`error ${message}`);

if (errors.length > 0) {
  console.error(`\n${errors.length} error(s), ${warnings.length} warning(s) across ${skillNames.length} skill(s).`);
  process.exit(1);
}

console.log(`ok  ${skillNames.length} skill(s) validated, ${warnings.length} warning(s).`);
