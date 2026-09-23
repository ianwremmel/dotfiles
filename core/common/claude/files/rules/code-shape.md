# Code shape

- Name functions with verbs: `parseConfig`, not `configParser`; `sendEmail`,
  not `email`. Predicates are questions: `isReady`, `hasPermission`,
  `canRetry`. Factories keep their verb: `createClient`. React components stay
  nouns and hooks stay `useX`.
- Keep source files under a few hundred lines. A longer file can't be read
  whole and turns every change into a large diff. Split by responsibility.
- Keep pull requests under 800 changed lines, and smaller when you can, not
  counting lockfiles and generated code. A change that can't fit is several
  changes; stack them.
