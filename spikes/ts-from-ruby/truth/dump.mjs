// Prints, as JSON, what ng-nudge's own code collects from a fixture project.
// Usage: node truth/dump.mjs NG_NUDGE_CLONE FIXTURE_DIR
// NG_NUDGE_CLONE is a checkout of ng-nudge with `npm ci` run in it.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { readdirSync } from 'node:fs';

const [clone, fixture] = process.argv.slice(2).map((p) => resolve(p));
const load = (rel) => import(pathToFileURL(resolve(clone, rel)).href);
const { Project } = await load('node_modules/ts-morph/dist/ts-morph.js');
const { ComponentApi } = await load('lib/artifact/api.js');
const { InterfaceApi } = await load('lib/artifact/interface-api.js');
const { createProjectView } = await load('lib/artifact/project-view.js');

const srcDir = resolve(fixture, 'src');
const project = createProjectView(new Project({ tsConfigFilePath: resolve(fixture, 'tsconfig.json') }), srcDir);

const names = (map) => [...map.keys()].sort();
const api = (file) => {
  const a = ComponentApi.from(file, project);
  return a && { inputs: names(a.inputs), outputs: names(a.outputs) };
};
const out = {};
for (const dir of readdirSync(resolve(srcDir, 'app'), { withFileTypes: true })) {
  if (!dir.isDirectory() || !/^c\d/.test(dir.name)) continue;
  const base = `app/${dir.name}/${dir.name}.component`;
  const comp = ComponentApi.from(`${base}.ts`, project);
  const stub = ComponentApi.from(`${base}.stub.ts`, project);
  const iface = InterfaceApi.from(`${base}.i.d.ts`, project);
  const violations = [];
  if (comp && stub) for (const m of comp.membersMissingFrom(stub)) violations.push(`stub missing ${m}`);
  if (comp && iface) for (const m of comp.membersMissingFrom(iface)) violations.push(`interface missing ${m}`);
  out[dir.name] = { component: api(`${base}.ts`), stub: api(`${base}.stub.ts`), interface: [...iface.properties].sort(), violations };
}
console.log(JSON.stringify(out, null, 2));
