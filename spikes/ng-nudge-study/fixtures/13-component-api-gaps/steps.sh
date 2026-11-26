# The component's public inputs are id and tone (inherited from Labelled, in
# another file), caption (label's alias), hint (a decorated property with no
# initializer), value (a model, so also an output valueChange), and size (a
# setter). Its other output is changed. The stub has only caption. ng-nudge
# follows the base class, reports label though the stub has its alias, and
# misses hint, value, valueChange, size and changed.
show cat src/app/field/field.component.ts
show cat src/app/field/field.component.stub.ts
nudge
# A stub class with no @Component decorator is not compared at all.
cat > src/app/field/field.component.stub.ts <<'TS'
export class FieldStubComponent {}
TS
nudge
