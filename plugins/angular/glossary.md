# Glossary of the Angular plugin

The words the Angular plugin uses beyond Angular's. Its roles, component, directive, pipe, service, guard, resolver, and interceptor, and a component's inputs and outputs mean what [Angular](https://angular.dev/) means by them. The words every user of CrossLint shares are in [the glossary](../../docs/glossary.md).

| Word | Meaning | Avoid |
| --- | --- | --- |
| **stub** | A component's `.component.stub.ts`, whose `@Component` class has every input and output the component has. | mock, fake |
| **interface** | A component's `.component.i.d.ts`, which contains one TypeScript interface whose properties name every input and output the component has. The general TypeScript sense of the word is written as "TypeScript interface". | |
| **base path** | An artifact's [key](../../docs/reference/plugin-glossary.md#declaring), in the form ng-nudge's debt files hold: its primary piece's path, relative to `src-dir`, without `.ROLE.ts`, such as `app/card/card` for `src/app/card/card.component.ts`. A debt entry can hold it in place of the artifact's name, which is its primary piece's path. | |
