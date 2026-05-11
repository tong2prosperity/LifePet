#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const etsRoot = path.join(root, 'entry/src/main/ets');
const failures = [];

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const item = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(item));
    } else if (entry.isFile() && item.endsWith('.ets')) {
      files.push(item);
    }
  }
  return files;
}

function matchingBrace(source, openIndex) {
  let depth = 0;
  for (let index = openIndex; index < source.length; index++) {
    const char = source[index];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }
  return -1;
}

function declaredThisTargets(body) {
  const targets = new Set();
  const methodRegex = /(?:^|\n)\s*(?:(?:private|public|protected|static|async)\s+)*([A-Za-z_]\w*)\s*\([^;{}]*\)\s*(?::[^\n{;]+)?\s*\{/g;
  const getterRegex = /(?:^|\n)\s*get\s+([A-Za-z_]\w*)\s*\(/g;
  const fieldRegex = /(?:^|\n)\s*(?:(?:@[A-Za-z]+(?:\([^)]*\))?\s*)+)?(?:(?:private|public|protected|readonly|static)\s+)*([A-Za-z_]\w*)\??\s*(?::|=)/g;
  const callbackFieldRegex = /(?:^|\n)\s*([A-Za-z_]\w*)\s*:\s*\([^)]*\)\s*=>/g;

  for (const match of body.matchAll(methodRegex)) {
    targets.add(match[1]);
  }
  for (const match of body.matchAll(getterRegex)) {
    targets.add(match[1]);
  }
  for (const match of body.matchAll(fieldRegex)) {
    targets.add(match[1]);
  }
  for (const match of body.matchAll(callbackFieldRegex)) {
    targets.add(match[1]);
  }
  return targets;
}

for (const file of walk(etsRoot)) {
  const source = fs.readFileSync(file, 'utf8');
  const scopeRegex = /\b(?:struct|class)\s+(\w+)/g;
  let scopeMatch;

  while ((scopeMatch = scopeRegex.exec(source)) !== null) {
    const openIndex = source.indexOf('{', scopeRegex.lastIndex);
    if (openIndex < 0) {
      continue;
    }
    const closeIndex = matchingBrace(source, openIndex);
    if (closeIndex < 0) {
      failures.push(`${path.relative(root, file)}:${scopeMatch[1]} has unmatched braces`);
      continue;
    }

    const body = source.slice(openIndex + 1, closeIndex);
    const allowedTargets = declaredThisTargets(body);
    for (const callMatch of body.matchAll(/this\.([A-Za-z_]\w*)\b/g)) {
      const target = callMatch[1];
      if (!allowedTargets.has(target)) {
        failures.push(`${path.relative(root, file)}:${scopeMatch[1]} references this.${target} without a local method, getter, field, or callback`);
      }
    }
    scopeRegex.lastIndex = closeIndex + 1;
  }
}

if (failures.length > 0) {
  console.error('ArkTS this-reference checks failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('ArkTS this-reference checks passed.');
