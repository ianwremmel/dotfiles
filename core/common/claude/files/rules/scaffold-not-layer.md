# Scaffold, don't layer

Layering builds finished slabs bottom-up: data layer, then service layer, then
API. Nothing fits together until the end. Scaffold instead: implement
outside-in, and at every step test from the newest unit outward.

## Implement outside-in

Start at the package's public interface. Write all of it, typed, with every
entry point throwing NotImplemented (or whatever fits the language). Write
tests against that interface; for now they assert NotImplemented. Then
implement one step inward: the first thing the interface needs, stubbed the
same way. Repeat until nothing throws NotImplemented.

In a typed language, don't test that the interface has the right shape. The
compiler does that.

## Test from the newest unit outward

After each step inward, write tests for the unit you just built, then walk
back out to the interface revising every test on the way: what asserted
NotImplemented now asserts real behavior, and what passed against a stub now
runs against the real thing. Tests are expected to change at every step; a
test that never changed after its unit's dependencies were implemented was
probably not testing them.

The innermost units get the edge-case tests, because that's where inputs are
cheap to enumerate; guard combinations that should never occur with
assertions rather than tests. Each outer layer's tests assume the inner ones
hold.

## The test

At any commit: does the package compile, do all tests pass, and can a reader
see from the interface what is built and what still throws NotImplemented?
