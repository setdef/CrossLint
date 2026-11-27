# Glossary

The words CrossLint's checking is made of, with the meaning each has here. A word only one plugin uses, such as the debt plugin's entries or the Angular plugin's stubs, is defined in that plugin's glossary, and the words for writing a plugin are in [the glossary for plugin authors](reference/plugin-glossary.md).

| Word | Meaning | Avoid |
| --- | --- | --- |
| **artifact** | A logical unit of a project, such as an Angular component, an entity in a C# domain model, a Rails route, or the project's list of debt. An artifact has a name, such as `app/card/card` or `GET /cart`, and CrossLint calls it by that name in every message and debt entry. It has pieces, and it is not a file. | file, set of files |
| **piece** | One of an artifact's files, or a part of a file, any of which may be missing: an Angular component's `.component.ts`, `.component.html`, and `.spec.ts`, or a Vue component's `<template>`, `<script>`, and `<style>`. One piece is primary: the one where the artifact is declared, such as a route's line in `config/routes.rb`, by which CrossLint usually finds it. | part, companion |
| **role** | What kind of artifact one is, such as a component, a service, or a route. | |
| **policy** | When rules apply: to which artifacts of a role, such as every component whose stub exists. | |
| **rule** | One check of one artifact, such as "the stub exists" or "the stub has every input the component has". | |
| **violation** | What a rule reports when an artifact fails it, with its severity: CrossLint fails the check for an error, and for a warning only under `--warnings=error`. | offense, problem |
| **plugin** | Roles, policies, and rules that belong together, in a folder with a `plugin.kdl` that declares them. To use a plugin, list it in the project's configuration. | extension, preset |
