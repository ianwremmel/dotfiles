# Push feature branches to themselves, never the default branch

When you open a branch for a change, a careless push can land on the default
branch (`master`/`main`) instead of the branch you just made. On a protected
default that fails loudly; on an unprotected one it silently commits straight to
the trunk you were trying to avoid.

The cause is the new branch's upstream pointing at the default. If you create the
branch tracking the default — `git checkout -b foo origin/master`, or any
`--track`/`-t` onto `origin/<default>` — its upstream is `origin/master`. With
`push.default = upstream` (or `tracking`), `git push` and even
`git push origin foo` then resolve the destination through that upstream and aim
at `master`.

Do this instead:

- Create the branch without tracking the default. `git switch -c <branch>` from
  your current HEAD. If you need to start from the latest default, fetch first
  and branch with no tracking: `git fetch origin && git switch -c <branch>
  --no-track origin/<default>`.
- Push with an explicit source and set the branch's own upstream:
  `git push -u origin HEAD`. HEAD resolves to the current branch and creates a
  same-named remote branch regardless of `push.default`. When in doubt, spell
  out both ends: `git push -u origin <branch>:<branch>`.
- Read the push output before moving on. It must say `<branch> -> <branch>`. If
  it says `<branch> -> master` (or `-> main`), stop — your upstream is wrong. Fix
  it with `git branch --set-upstream-to=origin/<branch>` (or re-push with the
  explicit `<branch>:<branch>` refspec). Never `git push --force` to get past it.

Then open the PR from the branch against the default
(`gh pr create --base <default> --head <branch>`).
