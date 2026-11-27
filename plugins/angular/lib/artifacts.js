// SPDX-FileCopyrightText: 2026 Over The Top Marketing
// SPDX-FileCopyrightText: 2026 setdef
// SPDX-License-Identifier: MIT

// The Angular plugin's artifacts: ng-nudge's seven roles, each found by
// {path}.ROLE.ts inside src-dir, and each role the configuration's role
// settings change or add, as ng-nudge's artifact registry finds its
// built-in roles and the roles rc.json changes or adds
// (lib/config/registry/artifact.registry.js and
// lib/config/artifact-definition.js). Each artifact's key is ng-nudge's
// base path, its primary piece's path relative to src-dir without
// .ROLE.ts, so that an entry of a debt file moved from ng-nudge names it.
// From ng-nudge, the port takes a role's patterns and expectations from
// CrossLint's settings in place of rc.json, and checks every setting.

export const ROLES = ['component', 'directive', 'pipe', 'service', 'guard', 'resolver', 'interceptor'];

// Where a component's other pieces are: its file, with .ts replaced.
// ng-nudge reads the stylesheets too.
const COMPONENT = { stub: '.stub.ts', interface: '.i.d.ts', css: '.css', scss: '.scss' };

// A role can expect only a spec: ng-nudge checks no other piece of every
// artifact of a role.
const EXPECTED = ['spec'];

// A mistake in one of the plugin's settings, on the setting's line.
export class Mistake extends Error {
  line;

  constructor(message, setting) {
    super(message);
    this.line = setting.line;
  }
}

// The artifacts the settings declare, as CrossLint takes them from a
// helper. Throws Mistake at the first setting it can't use.
export function declare(settings) {
  const found = once(settings);
  const src = folder(found.get('src-dir'), 'src-dir', 'src');
  const tsconfig = folder(found.get('tsconfig'), 'tsconfig', 'tsconfig.json');
  const roles = new Map(ROLES.map((role) => [role, { files: `{path}.${role}.ts`, expects: EXPECTED, optional: true }]));
  for (const setting of settings.filter((each) => each.name === 'role')) role(roles, setting);
  const within = (pattern) => (src === '' ? pattern : `${src}/${pattern}`);
  return [...roles].map(([name, given]) => {
    const stem = given.files.slice(0, -'.ts'.length);
    const pieces = Object.fromEntries(given.expects.map((piece) => [piece, within(`${stem}.spec.ts`)]));
    if (name === 'component') {
      for (const [piece, suffix] of Object.entries(COMPONENT)) pieces[piece] = within(stem + suffix);
      pieces.tsconfig = tsconfig;
    }
    // node-glob, which ng-nudge's patterns were, skips what starts with a dot.
    const key = given.files.endsWith(`.${name}.ts`) ? given.files.slice(0, -`.${name}.ts`.length) : given.files;
    return { name, primary: within(given.files), pieces, key, optional: given.optional, dotfiles: false };
  });
}

// The settings that are given once, by name.
function once(settings) {
  const found = new Map();
  for (const setting of settings.filter((each) => each.name !== 'role')) {
    const first = found.get(setting.name);
    if (first) throw new Mistake(`${setting.name} is set twice; the first is on line ${first.line}`, setting);
    found.set(setting.name, setting);
  }
  return found;
}

// A string as Ruby's String#dump writes it, which CrossLint's messages use.
const dump = (text) => JSON.stringify(text);

// What a value from the configuration reads as in a message.
const shown = (value) => (typeof value === 'string' ? dump(value) : String(value));

// The path a setting gives, relative to the project's root, with no ./
// or trailing /, or the default when the setting isn't given.
function folder(setting, name, fallback) {
  if (!setting) return fallback;

  const [path] = setting.arguments;
  if (setting.arguments.length !== 1 || typeof path !== 'string' || Object.keys(setting.properties).length > 0 || setting.children.length > 0) {
    throw new Mistake(`${name} takes one path and nothing else, as in ${name} ${dump(fallback)}`, setting);
  }

  const segments = path.split('/').filter((segment) => segment !== '' && segment !== '.');
  if (path.startsWith('/') || /^[A-Za-z]:/.test(path) || segments.includes('..') || path.includes('\\') || /[{}]/.test(path)) {
    throw new Mistake(`${name} takes a path inside the project, relative to its root, with / between folders, not ${dump(path)}`, setting);
  }
  if (segments.length === 0 && name === 'tsconfig') throw new Mistake(`${name} takes a file's path, not ${dump(path)}`, setting);

  return segments.join('/');
}

function role(roles, setting) {
  const [name] = setting.arguments;
  if (setting.arguments.length !== 1 || typeof name !== 'string' || !/^[A-Za-z0-9_-]+$/.test(name)) {
    throw new Mistake('role takes one name of letters, digits, - and _, as in role "store" files="{path}.store.ts"', setting);
  }
  const first = roles.get(name)?.line;
  if (first) throw new Mistake(`role ${dump(name)} is set twice; the first is on line ${first}`, setting);

  const unknown = Object.keys(setting.properties).filter((key) => key !== 'files');
  if (unknown.length > 0) throw new Mistake(`role takes files= and nothing else, not ${unknown[0]}=`, setting);

  const { files } = setting.properties;
  if (files !== undefined && !isPattern(files)) {
    throw new Mistake(`role ${dump(name)} takes files= as a path pattern ending in .ts, relative to src-dir`, setting);
  }

  roles.set(name, { files: files ?? `{path}.${name}.ts`, expects: expects(name, setting), optional: files === undefined && roles.has(name), line: setting.line });
}

// Whether files is a path pattern ending in .ts inside src-dir, by the
// rules of CrossLint's path patterns: not empty, no \, only {path} and
// {name} as placeholders, and no brace that pairs with nothing.
function isPattern(files) {
  if (typeof files !== 'string' || !files.endsWith('.ts') || files.startsWith('/') || files.split('/').includes('..') || files.includes('\\')) {
    return false;
  }
  const placeholders = [...files.matchAll(/\{([^{}]*)\}/g)].map((match) => match[1]);
  return placeholders.every((placeholder) => placeholder === 'path' || placeholder === 'name') && !/[{}]/.test(files.replace(/\{[^{}]*\}/g, ''));
}

// The pieces a role's block says it expects, or a spec when it has no
// block.
function expects(name, setting) {
  const { children } = setting;
  if (children.length === 0) return EXPECTED;

  const [child] = children;
  if (children.length !== 1 || child.name !== 'expects' || Object.keys(child.properties).length > 0 || child.children.length > 0) {
    throw new Mistake(`role ${dump(name)} takes one thing in its block, expects PIECE ...`, children.find((each) => each.name !== 'expects') ?? children.at(-1));
  }

  const unknown = child.arguments.find((piece) => !EXPECTED.includes(piece));
  if (unknown !== undefined) throw new Mistake(`role ${dump(name)} expects ${shown(unknown)}, and a role can expect only "spec"`, child);

  return child.arguments;
}
