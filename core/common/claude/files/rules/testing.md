# Testing

## Mock at the boundaries, through a wrapper you own

Mocks belong where the process leaves the machine: HTTP, sockets, the
filesystem, the clock, the database. Everything inside that line runs for
real. The database is the boundary worth crossing: a mocked database proves
little, so run a real one (in-memory engine or container) when the project
has a harness for it.

Don't mock the primitive; mock the thin wrapper around it. Mocking `fetch`
means faking HTTP; mocking `fetchUser` means returning a user. Write those
wrappers on purpose: a boundary should have a small, typed function in front
of it that tests can replace. The same goes for a database you can't run.

## Integration over isolation

A "unit" test that mocks every import of the file under test proves only that
the file calls its imports. The unit is a public interface plus everything it
pulls in up to the boundary above.

Isolating one file is the exception: worth it when you need to push many inputs
through one function and its dependencies would only add noise, e.g. you care
which dependency gets dispatched, not what it does. Say why in the test.

## Blackbox by default

Test through the public interface and assert on what comes out. Don't assert on
internal state, private helpers, or call order. Whitebox assertions are fine in
the isolation exception above, or when the effect is invisible from the
interface: a cache write, a metric emitted, a call deduplicated.

## Red before green

Write the test first and watch it fail for the right reason. Then write the
implementation that makes it pass. A test written after the code tends to
assert what the code does rather than what it should do.

## Assert invalid combinations instead of testing them

Don't enumerate every combination of inputs to prove each is handled. Test the
inputs you want to work and the rejections you expect to see in practice. For
combinations that should never occur, add a runtime assertion that says so and
stop there. An assertion documents the invariant and fails loudly if the
world disagrees; a test for it costs maintenance forever.

## No tautological tests

A test is tautological if nothing that matters could make it fail:

- a stub returns X and the test asserts X
- the expected value is computed with the same logic as the code under test
- it asserts a constant has its value, a function exists, or a type is a type
  (the compiler already checks this)

Delete them. They cost maintenance and give false confidence.

## The test

Of each test, ask: what bug would make this fail? If none, delete it. If the
answer is "the mock changed", move the mock outward.
