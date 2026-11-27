// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// The Angular plugin's helper, which declares its artifacts and runs its
// rules that read TypeScript, as ng-nudge's codebase and verification task
// find artifacts and run rules on them (lib/codebase.js and
// lib/verification-task.js). CrossLint sends it one request per line of
// JSON, in the project's root:
//
// - {"settings": [SETTING, ...]}, once, for the artifacts: it answers
//   {"artifacts": [ARTIFACT, ...]}, or {"mistake": {"message": TEXT,
//   "line": LINE}} for a setting it can't use.
// - {"rule": NAME, "artifact": ARTIFACT}, for each component a policy
//   applies the rule to: it answers {"violations": [{"message": TEXT,
//   "detail": TEXT}, ...]}.
//
// Anything else that goes wrong is {"error": MESSAGE}. The rules load
// ts-morph only when CrossLint first asks for one, so declaring the
// artifacts reads no TypeScript.
import { createInterface } from 'node:readline';
import { declare, Mistake } from './artifacts.js';

const codebases = new Map();

let rules;

async function check({ rule, artifact }) {
  rules ??= await import('./rule/index.js');
  const { Codebase } = await import('./codebase.js');
  const { Component } = await import('./artifact/component.artifact.js');
  const RuleClass = [rules.StubMatchesComponent, rules.InterfaceMatchesComponent].find((each) => each.name === rule);
  if (!RuleClass) throw new Error(`has no rule ${rule}`);

  const { tsconfig, stub, interface: iface } = artifact.pieces;
  if (!tsconfig.exists) throw new Error(`reads TypeScript with ${tsconfig.path}, the tsconfig setting's file, which doesn't exist`);
  if (!codebases.has(tsconfig.path)) codebases.set(tsconfig.path, new Codebase(tsconfig.path));
  const component = new Component(codebases.get(tsconfig.path), { path: artifact.path, stub: stub.path, interface: iface.path });
  return { violations: new RuleClass(component).violations };
}

export async function answer(request) {
  if (!('settings' in request)) return check(request);

  try {
    return { artifacts: declare(request.settings) };
  } catch (error) {
    if (error instanceof Mistake) return { mistake: { message: error.message, line: error.line } };
    throw error;
  }
}

for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  let reply;
  try {
    reply = await answer(JSON.parse(line));
  } catch (error) {
    reply = { error: error.message };
  }
  process.stdout.write(`${JSON.stringify(reply)}\n`);
}
