#pragma once

// ============================================================================
// GENERATED FILE -- DO NOT EDIT.
// Header-only twin of fsm.ixx (the C++20 module), produced by
// scripts/gen_fsm_hpp.py. fsm.ixx is the source of truth: edit it and re-run
//   py -I scripts/gen_fsm_hpp.py
// This header exists so CMake/Qt consumers (e.g. fsm_visualizer) can use the
// same generic DFA without C++ modules / `import std`.
// ============================================================================

// fsm uses C++20 concepts and <ranges>. Fail early with a clear message on a
// too-old toolchain (e.g. the MinGW 8.1 kit) instead of a wall of errors.
#if defined(__GNUC__) && !defined(__clang__) && (__GNUC__ < 11)
#  error "fsm.hpp requires a C++20 compiler (GCC >= 11). Point the MinGW kit at the Qt 6.8 bundled MinGW 13.1.0, not MinGW 8.1."
#endif

#include <concepts>
#include <functional>
#include <map>
#include <ranges>
#include <set>
#include <utility>
#include <vector>

namespace fsm {
  /// <summary>
  /// Constraint for a DFA input symbol (and state): copyable and totally ordered.
  /// </summary>
  /// <remarks>
  /// Symbols and states are stored as keys of std::map / std::set, which order
  /// them with operator&lt;, so a total ordering is required.
  /// </remarks>
  template <class T>
  concept fsm_symbol = std::copyable<T> && std::totally_ordered<T>;

  /// <summary>
  /// Constraint for a DFA state: an fsm_symbol that is also default-initializable.
  /// </summary>
  /// <remarks>
  /// The machine keeps the start and current states as plain members, which are
  /// default-constructed before any state is configured.
  /// </remarks>
  template <class T>
  concept fsm_state = fsm_symbol<T> && std::default_initializable<T>;

  /// <summary>
  /// A single step of the transition function delta: from --symbol--> to.
  /// </summary>
  /// <typeparam name="State">The state type.</typeparam>
  /// <typeparam name="Symbol">The input symbol type.</typeparam>
  template <fsm_state State, fsm_symbol Symbol>
  struct transition {
    State from;    ///< State the machine was in.
    Symbol symbol; ///< Input symbol that triggered the step.
    State to;      ///< State the machine moved to.
  };

  /// <summary>
  /// Policy for how step()/run() treat an input that has no defined (or
  /// guard-passing) transition from the current state.
  /// </summary>
  enum class on_undefined {
    halt,   ///< Machine becomes non-live and rejects all further input (DFA / language semantics).
    ignore, ///< Machine stays in its current state and keeps running (controller / GUI semantics).
  };

  /// <summary>
  /// Deterministic finite-state machine M = (Sigma, S, s0, delta, F).
  /// </summary>
  /// <remarks>
  ///   Sigma   the input alphabet (Symbol values); 
  ///   S       the set of states (State values); 
  ///   s0      the start state; 
  ///   delta   the partial transition function S x Sigma -&gt; S; 
  ///   F       the set of accepting states (F subset of S). 
  /// State and Symbol need only be totally ordered (usable as std::map keys), which 
  /// keeps the machine fully generic over e.g. char, int, enum or string. 
  /// Build it with the chainable start/accept/on/on_entry/on_exit builders, then drive
  /// it with reset/step/run, or query a word directly with accepts.
  /// </remarks>
  /// <typeparam name="State">The state type (see fsm_state).</typeparam>
  /// <typeparam name="Symbol">The input symbol type (see fsm_symbol).</typeparam>
  template <fsm_state State, fsm_symbol Symbol>
  class dfa {
  public:
    /// <summary>
    /// A transition of this machine: from --symbol--> to.
    /// </summary>
    using transition_t = transition<State, Symbol>;
    
    /// <summary>
    /// Observer callback invoked once per accepted transition.
    /// </summary>
    using observer_t = std::function<void(const transition_t&)>;

    /// <summary>
    /// Optional predicate guarding a transition; the transition fires only when it
    /// returns true. An empty guard always passes.
    /// </summary>
    using guard_t = std::function<bool()>;

    // --- Builder API (chainable) -------------------------------------------

    /// <summary>
    /// Sets the start state of the DFA.
    /// </summary>
    /// <param name="s">The state to set as the start state.</param>
    /// <returns>A reference to this DFA.</returns>
    dfa& start(State s) {
      start_ = std::move(s);
      has_start_ = true;
      return *this;
    }

    /// <summary>
    /// Marks a state as accepting.
    /// </summary>
    /// <param name="s">The state to mark as accepting.</param>
    /// <returns>A reference to this DFA.</returns>
    dfa& accept(State s) {
      accepting_.insert(std::move(s));
      return *this;
    }

    /// <summary>
    /// Adds an unconditional transition from `from` to `to` on `symbol`.
    /// </summary>
    /// <param name="from">The state from which the transition begins.</param>
    /// <param name="symbol">The symbol that triggers the transition.</param>
    /// <param name="to">The state to transition to.</param>
    /// <returns>A reference to this DFA.</returns>
    dfa& on(State from, Symbol symbol, State to) {
      delta_[std::move(from)][std::move(symbol)] = edge{std::move(to), {}};
      return *this;
    }

    /// <summary>
    /// Adds a guarded transition: it fires on `symbol` only while `guard` returns
    /// true. When the guard fails, the input is treated as undefined (see
    /// undefined()), modelling conditional transitions such as the real console's
    /// "pacing enabled" check.
    /// </summary>
    /// <param name="from">The state from which the transition begins.</param>
    /// <param name="symbol">The symbol that triggers the transition.</param>
    /// <param name="to">The state to transition to.</param>
    /// <param name="guard">Predicate that must hold for the transition to fire.</param>
    /// <returns>A reference to this DFA.</returns>
    dfa& on(State from, Symbol symbol, State to, guard_t guard) {
      delta_[std::move(from)][std::move(symbol)] = edge{std::move(to), std::move(guard)};
      return *this;
    }

    /// <summary>
    /// Registers an action to run when the specified state is entered.
    /// </summary>
    /// <param name="state">The state for which to register the entry action.</param>
    /// <param name="action">The function to run when the state is entered.</param>
    /// <returns>A reference to this dfa instance.</returns>
    /// <remarks>
    /// Entry action (Moore-style): invoked every time `state` becomes active --
    /// on each transition into it, and for the start state at reset(). Not fired
    /// by the pure accepts() query.
    /// </remarks>
    dfa& on_entry(State state, std::function<void()> action) {
      entry_[std::move(state)] = std::move(action);
      return *this;
    }

    /// <summary>
    /// Registers an action to run when a transition leaves the specified state.
    /// </summary>
    /// <remarks>
    /// Fired just before the destination state's entry action -- the per-transition
    /// order is exit(from) -&gt; observer -&gt; entry(to). Symmetric with on_entry.
    /// Only fires on a real transition: never on reset() (a hard restart), on a
    /// guard-rejected or undefined input, or from the pure accepts() query.
    /// </remarks>
    /// <param name="state">The state for which to register the exit action.</param>
    /// <param name="action">The function to run when the state is exited.</param>
    /// <returns>A reference to this dfa instance.</returns>
    /// <remarks>
    /// Exit action (Moore-style): invoked every time `state` is left -- on each
    /// transition out of it.
    /// </remarks>
    dfa& on_exit(State state, std::function<void()> action) {
      exit_[std::move(state)] = std::move(action);
      return *this;
    }

    /// <summary>
    /// Chooses how step()/run() react to an input with no defined (or guard-passing) 
    /// transition. Defaults to on_undefined::halt.
    /// </summary>
    /// <param name="policy">halt (DFA / language) or ignore (controller / GUI).</param>
    /// <returns>A reference to this DFA.</returns>
    dfa& undefined(on_undefined policy) {
      undefined_ = policy;
      return *this;
    }

    // --- Reactive hook ------------------------------------------------------
    // Push-based notification fired once per accepted transition. Adapters
    // (e.g. an RxCpp subject) subscribe here to expose the transition stream
    // as an observable.

    /// <summary>
    /// Stores the provided observer as the subscriber.
    /// </summary>
    /// <param name="observer">The observer to store.</param>
    void subscribe(observer_t observer) { observer_ = std::move(observer); }

    // --- Live execution -----------------------------------------------------

    /// <summary>
    /// Resets the current state to the start state and invokes its entry action if a start state is configured.
    /// </summary>
    void reset() {
      current_ = start_;
      live_ = has_start_;
      if(live_) fire_entry(current_);
    }

    /// <summary>
    /// Returns the current state.
    /// </summary>
    /// <returns>A const reference to the current state.</returns>
    const State& current() const { return current_; }

    /// <summary>
    /// Indicates whether the machine is still live, i.e. it has not yet read an
    /// undefined (state, symbol) pair.
    /// </summary>
    /// <returns>true while the machine is live; false once it is stuck.</returns>
    bool live() const { return live_; }

    /// <summary>
    /// Indicates whether the live machine is currently in an accepting state.
    /// </summary>
    /// <returns>true if the machine is live and its current state is in F.</returns>
    bool accepted() const { return live_ && accepting_.contains(current_); }

    /// <summary>
    /// Tests whether `symbol` would fire a transition right now, i.e. the live
    /// machine has a defined edge for it from the current state whose guard (if
    /// any) currently passes. Side-effect free.
    /// </summary>
    /// <remarks>
    /// Lets a UI ask the machine which inputs are valid instead of hard-coding
    /// per-state rules: step(symbol) will fire iff can(symbol) was true.
    /// </remarks>
    /// <param name="symbol">The input symbol to test.</param>
    /// <returns>
    /// true if step(symbol) would fire a transition from the current state.
    /// </returns>
    bool can(const Symbol& symbol) const {
      if(!live_) return false;
      const edge* e = find_edge(current_, symbol);
      return e != nullptr && (!e->guard || e->guard());
    }

    /// <summary>
    /// Returns every symbol that would fire a transition from the current state
    /// right now (guards evaluated), in ascending symbol order. Empty when the
    /// machine is not live. Side-effect free.
    /// </summary>
    /// <returns>The symbols for which can() is currently true.</returns>
    std::vector<Symbol> available() const {
      std::vector<Symbol> result;
      if(!live_) return result;
      auto si = delta_.find(current_);
      if(si == delta_.end()) return result;
      for(const auto& [symbol, e] : si->second)
        if(!e.guard || e.guard()) result.push_back(symbol);
      return result;
    }

    /// <summary>
    /// Consumes a single input symbol, advancing the current state and firing the
    /// observer and the destination state's entry action.
    /// </summary>
    /// <param name="symbol">The input symbol to consume.</param>
    /// <returns>
    /// true if a transition fired (delta defined and any guard passed). Otherwise
    /// no transition is taken and the return is false; under on_undefined::halt the
    /// machine also becomes non-live, while under on_undefined::ignore it stays in
    /// its current state and remains usable.
    /// </returns>
    bool step(const Symbol& symbol) {
      if(!live_) return false;
      const edge* e = find_edge(current_, symbol);
      if(e == nullptr || (e->guard && !e->guard())) {
        if(undefined_ == on_undefined::halt) live_ = false;
        return false;
      }
      transition_t t{current_, symbol, e->to};
      fire_exit(current_);  // leaving `from`; fires only on a real transition
      current_ = e->to;
      if(observer_) observer_(t);
      fire_entry(current_);
      return true;
    }

    /// <summary>
    /// Feeds a whole sequence of symbols from the current configuration.
    /// </summary>
    /// <typeparam name="R">An input range whose elements are convertible to Symbol.</typeparam>
    /// <param name="input">The sequence of symbols to consume in order.</param>
    /// <returns>
    /// true if every symbol produced a transition. Under on_undefined::ignore the
    /// whole sequence is still consumed (undefined inputs are skipped); under
    /// on_undefined::halt the run stops at the first undefined input.
    /// </returns>
    template <std::ranges::input_range R>
      requires std::convertible_to<std::ranges::range_reference_t<R>, Symbol>
    bool run(const R& input) {
      bool all_defined = true;
      for(auto&& symbol : input) {
        if(!step(symbol)) {
          all_defined = false;
          if(!live_) break;  // halt policy killed the machine; nothing more to do
        }
      }
      return all_defined;
    }

    // --- Pure language query ------------------------------------------------

    /// <summary>
    /// Tests whether the machine accepts the given word, starting from s0.
    /// </summary>
    /// <remarks>
    /// Side-effect free: it neither mutates the live configuration (current state
    /// / live flag) nor fires the observer or entry actions.
    /// </remarks>
    /// <typeparam name="R">An input range whose elements are convertible to Symbol.</typeparam>
    /// <param name="input">The word to test.</param>
    /// <returns>true if the word drives s0 to an accepting state via defined transitions.</returns>
    template <std::ranges::input_range R>
      requires std::convertible_to<std::ranges::range_reference_t<R>, Symbol>
    bool accepts(const R& input) const {
      if(!has_start_) return false;
      State cur = start_;
      for(auto&& symbol : input) {
        const edge* e = find_edge(cur, symbol);
        if(e == nullptr || (e->guard && !e->guard())) return false;
        cur = e->to;
      }
      return accepting_.contains(cur);
    }

  private:
    /// <summary>
    /// A delta entry: the destination state plus an optional guard predicate.
    /// The guard is evaluated at run-time; if it returns false, the transition is skipped.
    /// </summary>
    struct edge {
      State to;
      guard_t guard;  // empty => always passes
    };

    /// <summary>
    /// Invokes the entry action registered for the state, if any.
    /// </summary>
    /// <param name="state">The state for which to invoke the entry action.</param>
    void fire_entry(const State& state) {
      if(auto it = entry_.find(state); it != entry_.end() && it->second) {
        it->second();
      }
    }

    /// <summary>
    /// Invokes the exit action registered for the state, if any.
    /// </summary>
    /// <param name="state">The state for which to invoke the exit action.</param>
    void fire_exit(const State& state) {
      if(auto it = exit_.find(state); it != exit_.end() && it->second) {
        it->second();
      }
    }

    /// <summary>
    /// Looks up the edge for (state, symbol), or nullptr if none exists.
    /// </summary>
    const edge* find_edge(const State& state, const Symbol& symbol) const {
      auto si = delta_.find(state);
      if(si == delta_.end()) return nullptr;
      auto ti = si->second.find(symbol);
      if(ti == si->second.end()) return nullptr;
      return &ti->second;
    }

    /// <summary>
    /// Stores the transition edges associated with each state and symbol.
    /// </summary>
    std::map<State, std::map<Symbol, edge>> delta_;

    /// <summary>
    /// Stores a callback for each state’s entry action.
    /// </summary>
    std::map<State, std::function<void()>> entry_;

    /// <summary>
    /// Stores exit callbacks indexed by state.
    /// </summary>
    std::map<State, std::function<void()>> exit_;

    /// <summary>
    /// The set of accepting states.
    /// </summary>
    std::set<State> accepting_;

    /// <summary>
    /// A default-initialized State object named start_.
    /// </summary>
    State start_{};

    /// <summary>
    /// Stores the current state and value-initializes it.
    /// </summary>
    State current_{};

    /// <summary>
    /// Tracks whether a start condition has been detected.
    /// </summary>
    bool has_start_ = false;

    /// <summary>
    /// Indicates whether the object is live; initialized to false.
    /// </summary>
    bool live_ = false;

    /// <summary>
    /// Initializes undefined_ with the halt behavior for undefined states.
    /// </summary>
    on_undefined undefined_ = on_undefined::halt;
    
    /// <summary>
    /// Declares a variable named observer_ of type observer_t.
    /// </summary>
    observer_t observer_;
  };
}  // namespace fsm
