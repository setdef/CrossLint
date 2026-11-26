# api.service.spec.ts exists, but tsconfig.json excludes spec files, the way
# an application tsconfig often does. ng-nudge reports it missing.
show ls src/app
show cat tsconfig.json
nudge
