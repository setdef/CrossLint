# Decision log

The few decisions CrossLint's structure rests on, one record each, in the order they were made. How each part works is in [the design documents](../design/README.md).

| Record | Decision |
| --- | --- |
| [0002](0002-the-engine-is-a-core-of-plain-ruby-objects-behind-ports.md) | The engine is a core of plain Ruby objects, and everything it reaches is an adapter behind a port |
| [0003](0003-a-plugin-reaches-the-engine-only-through-what-its-manifest-declares.md) | A plugin reaches the engine only through what its manifest declares, and adds commands under the plugin's name |
| [0004](0004-crosslint-is-ruby-and-a-plugins-code-may-be-in-any-language.md) | CrossLint is one program, in Ruby, and a plugin's code may be in any language |

To change a decision, write a new record with the next number, and delete the old one in the same change ([CONTRIBUTING](../../CONTRIBUTING.md#writing-things-down)).
