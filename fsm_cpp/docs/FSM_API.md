# `fsm::dfa<State, Symbol>` — API Reference

A generic, deterministic finite-state machine (DFA), the formal object
**M = (Σ, S, s₀, δ, F)**:

| Formal | Meaning | In the API |
|---|---|---|
| Σ | input alphabet | the `Symbol` type (e.g. an `enum class Event`) |
| S | set of states | the `State` type (e.g. an `enum class State`) |
| s₀ | start state | `start(s)` |
| δ | transition function | `on(from, symbol, to [, guard])` |
| F | accepting states | `accept(s)` |

The machine is **built once** with a chainable builder, then **run live** by
feeding one `Symbol` at a time to `step()`. It is deliberately generic and
side-effect-free about *behaviour*: it only moves between states. Anything
observable (logging, UI, I/O) is done by the caller through the `subscribe()`
transition hook and the `on_entry()` / `on_exit()` actions.

## Getting it

| Build | Include | Notes |
|---|---|---|
| MSVC / C++20 modules | `import fsm;` | canonical source `src/fsm/fsm.ixx` (uses `import std;`) |
| Any C++20 toolchain | `#include "fsm.hpp"` | header-only twin `core/fsm.hpp` (GCC ≥ 11); kept in sync with the module |

Both expose the identical `fsm::dfa` API described here.

## Template parameters

```cpp
template <fsm_state State, fsm_symbol Symbol>
class dfa;
```

- `fsm_symbol<T>` = `std::copyable<T> && std::totally_ordered<T>` — symbols and
  states are stored as `std::map` / `std::set` keys, so they must be orderable.
  Plain scoped enums satisfy this out of the box; so do `int`, `char`,
  `std::string`, etc.
- `fsm_state<T>` = `fsm_symbol<T> && std::default_initializable<T>` — the machine
  holds the current state as a plain member, so it must be default-constructible.

## Lifecycle at a glance

See **[FSM_API_lifecycle.svg](FSM_API_lifecycle.svg)** for the diagram.

```
construct ──► BUILD (chainable) ──► reset() ──► RUN ──► QUERY
                                                 │
   dfa<S,Sym> m;   start/accept/on/on_entry/   enter s0,   step(sym) / run(seq)   current()/live()/
                   on_exit/undefined/subscribe fire entry  loops here             accepted()/can()/available()
```

Three phases:

1. **Build** — define the machine. Every builder returns `dfa&`, so calls chain.
2. **Initialize** — `reset()` enters s₀, fires its entry action, and makes the
   machine *live*.
3. **Run / query** — `step()` / `run()` drive it; `current()`, `accepted()`,
   `can()`, `available()` inspect it. `accepts()` is a separate, pure path that
   never touches the live machine.

## Quick start

```cpp
import fsm;                 // or: #include "fsm.hpp"

enum class State { Locked, Open };
enum class Event { Coin, Push };

fsm::dfa<State, Event> turnstile;

// 1. BUILD
turnstile.start(State::Locked)
         .accept(State::Locked)
         .on(State::Locked, Event::Coin, State::Open)
         .on(State::Open,   Event::Push, State::Locked)
         .undefined(fsm::on_undefined::ignore);   // stray inputs are no-ops

// 2. INITIALIZE
turnstile.reset();                 // now in Locked, live

// 3. RUN / QUERY
turnstile.can(Event::Coin);        // true  — Coin is valid in Locked
turnstile.can(Event::Push);        // false — Push is not
turnstile.step(Event::Coin);       // Locked --Coin--> Open, returns true
turnstile.current();               // State::Open
```

## API reference

### Types

| Member | Definition |
|---|---|
| `transition_t` | `fsm::transition<State, Symbol>` — `{ State from; Symbol symbol; State to; }` |
| `observer_t` | `std::function<void(const transition_t&)>` |
| `guard_t` | `std::function<bool()>` — an empty guard always passes |

### Builder API (chainable, each returns `dfa&`)

| Method | Effect |
|---|---|
| `start(State s)` | Set s₀. Required before `reset()`. |
| `accept(State s)` | Add `s` to F (accepting/"idle-safe" states). May be called repeatedly. |
| `on(State from, Symbol sym, State to)` | Add an unguarded edge to δ. Re-adding the same `(from, sym)` overwrites (determinism: one target per pair). |
| `on(State from, Symbol sym, State to, guard_t guard)` | Guarded edge: fires only while `guard()` is true; otherwise the input is treated as undefined. |
| `on_entry(State s, std::function<void()> action)` | Moore entry action: fires every time `s` becomes active, including at `reset()`. |
| `on_exit(State s, std::function<void()> action)` | Fires when a real transition *leaves* `s` (see ordering below). |
| `undefined(on_undefined policy)` | How `step()`/`run()` treat an input with no firable edge. Default `halt`. |
| `subscribe(observer_t observer)` | Register the single transition observer (last call wins). |

### Initialize & live execution

| Method | Returns | Effect |
|---|---|---|
| `reset()` | `void` | Enter s₀, fire its entry action, become live. Call after building; call again to restart. |
| `step(const Symbol& sym)` | `bool` | Consume one symbol. `true` if a transition fired. See semantics below. |
| `run(const R& range)` | `bool` | Feed a sequence through `step()`. `true` iff every symbol fired. |
| `current()` | `const State&` | The current state. |
| `live()` | `bool` | Machine has not halted on an undefined input. |
| `accepted()` | `bool` | Live **and** current state ∈ F. |
| `can(const Symbol& sym)` | `bool` | Would `step(sym)` fire right now? (edge exists and guard passes). Side-effect free. |
| `available()` | `std::vector<Symbol>` | Every symbol for which `can()` is currently true, ascending. Empty if not live. |

### Pure language query

| Method | Returns | Effect |
|---|---|---|
| `accepts(const R& range)` | `bool` | Does the word drive s₀ to an accepting state via defined, guard-passing edges? **Does not** mutate the machine, fire actions, or run the observer; ignores the `on_undefined` policy (undefined ⇒ reject). |

### Free types

```cpp
template <fsm_state State, fsm_symbol Symbol>
struct transition { State from; Symbol symbol; State to; };

enum class on_undefined {
  halt,    // machine becomes non-live and rejects all further input (DFA semantics)
  ignore,  // machine stays put and keeps running (controller / GUI semantics)
};
```

## Semantics

**`step()` outcome.** With an edge for `(current, sym)` whose guard passes, the
transition fires and `step` returns `true`. Otherwise no transition is taken and
`step` returns `false`; under `on_undefined::halt` the machine also goes
non-live, while under `on_undefined::ignore` it stays in place and remains
usable.

**Side-effect ordering.** On a real transition the callbacks fire in this order:

```
on_exit(from)  ─►  observer(from, symbol, to)  ─►  on_entry(to)
```

`on_exit` fires **only** on a real transition — never on `reset()` (a hard
restart, not an exit), never on a guard-rejected or undefined input, and never
from `accepts()`.

**Moore entry on reset.** `reset()` fires `on_entry(s₀)` (entry actions run on
*every* entry, including the first). It does **not** fire any exit action or the
observer.

**`accepts()` vs `step()`/`run()`.** `accepts()` answers a language question
from s₀ with zero side effects — use it for acceptance testing. `step()`/`run()`
drive the live machine and fire all actions/observer — use them to run the
machine.

**Determinism.** Each `(from, symbol)` maps to at most one target; re-adding an
edge overwrites the previous one.

**Thread-safety.** A `dfa` is not synchronized. Drive it from one thread (e.g.
marshal inputs onto a single run-loop, as `ConsoleController` does).

## Worked examples

### 1. Language acceptance (pure)

```cpp
enum class Parity { Even, Odd };
fsm::dfa<Parity, char> m;
m.start(Parity::Even).accept(Parity::Even)
 .on(Parity::Even, '0', Parity::Even).on(Parity::Even, '1', Parity::Odd)
 .on(Parity::Odd,  '0', Parity::Odd ).on(Parity::Odd,  '1', Parity::Even);

m.accepts(std::string_view{"1010"});   // true  (even number of 1s)
m.accepts(std::string_view{"1"});      // false
// m is untouched: still not live (accepts() has no side effects).
```

### 2. Guard + entry/exit + observer + availability (controller style)

```cpp
enum class S { Ready, Charging };
enum class E { Prepare, Done };

bool pacingEnabled = false;
fsm::dfa<S, E> m;
m.start(S::Ready).accept(S::Ready)
 .on(S::Ready, E::Prepare, S::Charging, [&]{ return pacingEnabled; })  // guarded
 .on(S::Charging, E::Done, S::Ready)
 .undefined(fsm::on_undefined::ignore);

m.on_entry(S::Charging, []{ /* start charging */ });
m.on_exit (S::Charging, []{ /* stop charging  */ });
m.subscribe([](const auto& t){ /* log t.from --t.symbol--> t.to */ });

m.reset();                 // enter Ready (fires on_entry(Ready) if registered)
m.can(E::Prepare);         // false — guard blocks while pacing disabled
pacingEnabled = true;
m.can(E::Prepare);         // true
m.available();             // { E::Prepare }
m.step(E::Prepare);        // Ready --Prepare--> Charging: on_entry(Charging) fires
```

> In Generator3 this exact pattern backs the UI: `ConsoleController.availableEvents`
> is built from `available()`, and QML derives button `enabled` from it instead
> of hard-coding per-state checks.

## Build & test (canonical module)

```bat
:: from a VS 2026 developer environment
MSBuild tests\fsm.tests\fsm.tests.vcxproj /t:Build /p:Configuration=Debug /p:Platform=x64
vstest.console.exe tests\fsm.tests\build\x64\Debug\fsm.tests\fsm.tests.dll
```

The unit tests in `tests/fsm.tests/tests.cpp` exercise every API group
(acceptance, execution, undefined policy, guards, observer, entry, exit,
queries, genericity).
