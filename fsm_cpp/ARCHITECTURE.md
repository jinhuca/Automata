# FSM Architecture

A generic, header-light deterministic finite-state machine delivered as a C++20
module, with an RxCpp-based reactive transition stream, a console demo, and a
unit-test suite. Diagrams render in the VS / VS Code Markdown preview.

## Formal model → code

The machine implements the 5-tuple `M = (Σ, S, s0, δ, F)`:

| Formal      | Meaning                     | In `dfa<State, Symbol>`                  |
|-------------|-----------------------------|------------------------------------------|
| `Σ`         | input alphabet              | values of type `Symbol` (keys of `delta_`) |
| `S`         | set of states               | values of type `State`                   |
| `s0`        | start state                 | `start_` (set via `start()`)             |
| `δ`         | transition function S×Σ→S   | `delta_` : `map<State, map<Symbol,State>>` |
| `F`         | accepting states, F ⊆ S     | `accepting_` (set via `accept()`)        |

## Component & dependency view

```mermaid
graph TD
  subgraph Toolchain
    VS["Visual Studio 2026 · MSBuild · toolset v145"]
    VCPKG["vcpkg (manifest: vcpkg.json)"]
  end
  RX["rxcpp 4.1.1 (header-only)"]
  CPPUT["CppUnitTestFramework (VS native)"]
  STD["C++20 stdlib only<br/>map · set · function · ranges"]

  VCPKG -->|"restores"| RX

  subgraph SLN["FiniteStateMachine.sln"]
    FSM["fsm — static library<br/>C++20 module 'fsm'<br/>src/fsm/fsm.ixx"]
    DEMO["demo — console app<br/>src/demo/main.cpp"]
    TESTS["fsm.tests — test DLL<br/>tests/fsm.tests/tests.cpp"]
  end

  FSM -->|"uses"| STD
  DEMO -->|"import fsm"| FSM
  TESTS -->|"import fsm"| FSM
  DEMO -->|"#include rxcpp/rx.hpp"| RX
  TESTS -->|"links"| CPPUT

  VS -->|"builds"| SLN
```

The core `fsm` module depends only on the standard library. RxCpp is confined to
the **demo** (the reactive consumer), and the test framework to **fsm.tests**, so
the reusable machine stays dependency-free.

## Class view

```mermaid
classDiagram
  class dfa~State, Symbol~ {
    -delta_ : transition table for S x Sigma
    -entry_ : per-state entry actions
    -accepting_ : accepting states F
    -start_ : start state s0
    -current_ : live active state
    -has_start_ : bool
    -live_ : bool
    -observer_ : transition callback
    +start(State) dfa&
    +accept(State) dfa&
    +on(from, sym, to) dfa&
    +on_entry(State, action) dfa&
    +subscribe(observer) void
    +reset() void
    +step(Symbol) bool
    +run(range) bool
    +accepts(range) bool
    +current() State
    +live() bool
    +accepted() bool
  }

  class transition~State, Symbol~ {
    +from : State
    +symbol : Symbol
    +to : State
  }

  dfa --> transition : emits on each step
```

Three API groups: a **chainable builder** (`start`/`accept`/`on`/`on_entry`),
**live execution** (`reset`/`step`/`run` + `current`/`live`/`accepted`), and a
side-effect-free **language query** (`accepts`). The single `subscribe` hook is
the seam the reactive layer plugs into.

## Reactive runtime flow

Per `step()`: advance state → notify the Rx transition observer → fire the new
state's entry action. The pure `accepts()` query does none of this.

```mermaid
sequenceDiagram
  participant App as demo/main
  participant M as dfa
  participant Subj as rxcpp subject
  participant Pipe as "Rx pipeline (filter/map)"

  App->>M: on_entry(state, action)
  App->>M: subscribe(push -> subject)
  App->>M: reset()
  M-->>M: fire entry(start state)

  loop each symbol in the input word
    App->>M: step(symbol)
    M->>M: current = delta(current, symbol)
    M->>Subj: observer(transition{from, symbol, to})
    Subj->>Pipe: on_next(transition)
    Pipe-->>App: filtered / mapped events
    M-->>M: fire entry(new state)
  end

  App->>M: accepted()?  (live_ AND current in F)
```

## Build & test pipeline

```mermaid
graph LR
  MAN["vcpkg.json"] -->|"vcpkg install"| INST["vcpkg_installed/<br/>rxcpp headers"]
  INST --> BLD
  SRC["src/ + tests/"] --> BLD["msbuild FiniteStateMachine.sln"]
  BLD --> LIB["fsm.lib + fsm module .ifc"]
  BLD --> EXE["demo.exe"]
  BLD --> DLL["fsm.tests.dll"]
  DLL -->|"vstest.console"| RES["test results"]
```
