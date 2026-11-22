// Console control-state simulation.
//
// Models the ablation console's state machine `MainScreen::ControlState` from
// cap_gui_commercial_dev (src/libFarastar/screens/Therapy/mainscreen.{h,cpp})
// on top of the generic fsm::dfa. States and events mirror the real workflow:
// buttons (Prepare/Confirm/Deliver) and controller/timer reports drive the
// transitions, with abort and catheter-disconnect recovery edges.

#include <iostream>
#include <string_view>
#include <vector>

#include <rxcpp/rx.hpp>

import fsm;

namespace {

  // Mirrors MainScreen::ControlState (0..8).
  enum class State {
    CatheterDisconnected,
    SystemReady,
    Charging,
    Charged,
    PaceCapture,
    AblateReady,
    AblateActive,
    AblateComplete,
    Cooldown,
    Error,
  };

  // Events that drive ControlState in mainscreen.cpp.
  enum class Event {
    CatheterConnected,     // catheter plugged in / initialized
    CatheterDisconnected,  // catheter dropped out
    Prepare,               // prepareButton()  -> CHARGING
    ChargeComplete,        // chargingFinished()
    Pace,                  // pace capture started
    Confirm,               // confirmButton()  -> ABLATE_READY
    Deliver,               // deliverButton()  -> ABLATE_ACTIVE
    AblateComplete,        // ablateFinished()
    CooldownStart,         // startCooldown()
    CooldownComplete,      // cooldownFinished()
    Abort,                 // cancel back to CHARGED
    Fault,                 // a fault/error is raised
    ClearError,            // error acknowledged / cleared
  };

  // Human-readable label for a control state (matches the real ControlState enum).
  std::string_view name(State s) {
    switch(s) {
    case State::CatheterDisconnected: return "CATHETER_DISCONNECTED";
    case State::SystemReady:          return "SYSTEM_READY";
    case State::Charging:             return "CHARGING";
    case State::Charged:              return "CHARGED";
    case State::PaceCapture:          return "PACE_CAPTURE";
    case State::AblateReady:          return "ABLATE_READY";
    case State::AblateActive:         return "ABLATE_ACTIVE";
    case State::AblateComplete:       return "ABLATE_COMPLETE";
    case State::Cooldown:             return "COOLDOWN";
    case State::Error:                return "ERROR";
    }
    return "?";
  }

  // Human-readable label for an event.
  std::string_view name(Event e) {
    switch(e) {
    case Event::CatheterConnected:    return "CatheterConnected";
    case Event::CatheterDisconnected: return "CatheterDisconnected";
    case Event::Prepare:              return "Prepare";
    case Event::ChargeComplete:       return "ChargeComplete";
    case Event::Pace:                 return "Pace";
    case Event::Confirm:              return "Confirm";
    case Event::Deliver:              return "Deliver";
    case Event::AblateComplete:       return "AblateComplete";
    case Event::CooldownStart:        return "CooldownStart";
    case Event::CooldownComplete:     return "CooldownComplete";
    case Event::Abort:                return "Abort";
    case Event::Fault:                return "Fault";
    case Event::ClearError:           return "ClearError";
    }
    return "?";
  }

  // Builds the console control-state machine: start state, accepting (idle/safe)
  // states, and the full event-driven transition table.
  //
  // `pacingEnabled` is read live by a transition guard, mirroring the real
  // console where prepareButton()/deliverButton() require pacing to be enabled.
  fsm::dfa<State, Event> make_console(const bool& pacingEnabled) {
    using S = State;
    using E = Event;
    fsm::dfa<State, Event> m;

    m.start(S::CatheterDisconnected);
    // "Safe / idle" states where no energy is staged or delivered.
    m.accept(S::CatheterDisconnected).accept(S::SystemReady).accept(S::Charged);

    // Like the real console, an input that is not valid in the current state is
    // ignored (the machine stays put) rather than faulting the state machine.
    m.undefined(fsm::on_undefined::ignore);

    // Main therapy workflow. Prepare is guarded on pacing being enabled.
    m.on(S::CatheterDisconnected, E::CatheterConnected, S::SystemReady)
      .on(S::SystemReady, E::Prepare, S::Charging, [p = &pacingEnabled] { return *p; })
      .on(S::Charging, E::ChargeComplete, S::Charged)
      .on(S::Charged, E::Pace, S::PaceCapture)
      .on(S::PaceCapture, E::Confirm, S::AblateReady)
      .on(S::Charged, E::Confirm, S::AblateReady)
      .on(S::AblateReady, E::Deliver, S::AblateActive)
      .on(S::AblateActive, E::AblateComplete, S::AblateComplete)
      .on(S::AblateComplete, E::CooldownStart, S::Cooldown)
      .on(S::Cooldown, E::CooldownComplete, S::Charged);

    // Abort returns to CHARGED (mainscreen.cpp: state >= PACE_CAPTURE && < ABLATE_COMPLETE).
    m.on(S::PaceCapture, E::Abort, S::Charged)
      .on(S::AblateReady, E::Abort, S::Charged)
      .on(S::AblateActive, E::Abort, S::Charged);

    // Catheter can drop out of the working states (-> CATHETER_DISCONNECTED).
    m.on(S::SystemReady, E::CatheterDisconnected, S::CatheterDisconnected)
      .on(S::Charging, E::CatheterDisconnected, S::CatheterDisconnected)
      .on(S::Charged, E::CatheterDisconnected, S::CatheterDisconnected)
      .on(S::AblateReady, E::CatheterDisconnected, S::CatheterDisconnected);

    // A fault from ANY state drops the console into ERROR; clearing the error
    // returns it to the initial CATHETER_DISCONNECTED state, from which it
    // re-connects to SYSTEM_READY once the catheter is detected.
    m.on(S::CatheterDisconnected, E::Fault, S::Error)
      .on(S::SystemReady, E::Fault, S::Error)
      .on(S::Charging, E::Fault, S::Error)
      .on(S::Charged, E::Fault, S::Error)
      .on(S::PaceCapture, E::Fault, S::Error)
      .on(S::AblateReady, E::Fault, S::Error)
      .on(S::AblateActive, E::Fault, S::Error)
      .on(S::AblateComplete, E::Fault, S::Error)
      .on(S::Cooldown, E::Fault, S::Error)
      // A fault received while already in ERROR is handled explicitly as a
      // self-loop (so it is logged via the transition stream, not ignored).
      .on(S::Error, E::Fault, S::Error)
      .on(S::Error, E::ClearError, S::CatheterDisconnected);

    return m;
  }

  // Runs one scenario: reset the console, feed the event sequence, and report the
  // resulting state (halting early if an event is invalid in the current state).
  void drive(fsm::dfa<State, Event>& m, std::string_view title,
    const std::vector<Event>& events) {
    std::cout << "\n=== " << title << " ===\n";
    m.reset();
    std::cout << "  start: " << name(m.current()) << '\n';
    for(Event e : events) {
      if(!m.step(e)) {
        // Ignore mode: the event had no valid transition, so the console stays
        // in its current state and keeps running (as a real console would).
        std::cout << "    [ignored] " << name(e) << " has no effect in "
          << name(m.current()) << '\n';
      }
    }
    std::cout << "  final: " << name(m.current())
      << (m.accepted() ? "  [idle/safe]" : "  [busy]") << '\n';
  }

}  // namespace

int main() {
  // Live flag read by the Prepare guard (toggled between scenarios below).
  bool pacingEnabled = true;
  auto console = make_console(pacingEnabled);

  // Reactive transition log (RxCpp), fed by the DFA's subscribe hook.
  rxcpp::subjects::subject<fsm::transition<State, Event>> subject;
  auto bus = subject.get_subscriber();
  console.subscribe(
    [&bus](const fsm::transition<State, Event>& t) { bus.on_next(t); });
  subject.get_observable().subscribe([](const auto& t) {
    std::cout << "    [rx] " << name(t.from) << " --" << name(t.symbol)
      << "--> " << name(t.to) << '\n';
  });

  // Dedicated fault log: records every Fault event (including a repeat fault
  // that self-loops while already in ERROR).
  subject.get_observable()
    .filter([](const auto& t) { return t.symbol == Event::Fault; })
    .subscribe([](const auto& t) { 
      std::cout << "    [fault-log] Fault raised in " << name(t.from) << '\n';}
    );

  // Per-state simulation actions: fire whenever the console enters a state
  // (including the start state at reset), standing in for the real side effects
  // the console performs in each ControlState.
  auto sim = [](std::string_view msg) {
    return [msg] { std::cout << "    [sim] " << msg << '\n'; };
  };
  console.on_entry(State::CatheterDisconnected, sim("waiting for catheter connection"));
  console.on_entry(State::SystemReady, sim("system idle - ready to prepare"));
  console.on_entry(State::Charging, sim("charging capacitors..."));
  console.on_entry(State::Charged, sim("charged - awaiting confirm"));
  console.on_entry(State::PaceCapture, sim("pacing capture in progress"));
  console.on_entry(State::AblateReady, sim("armed - ready to deliver"));
  console.on_entry(State::AblateActive, sim("*** ENERGY DELIVERY ACTIVE ***"));
  console.on_entry(State::AblateComplete, sim("delivery complete - logging ablation"));
  console.on_entry(State::Cooldown, sim("cooling down..."));
  console.on_entry(State::Error, sim("!!! CONSOLE FAULT - therapy locked out !!!"));

  std::cout << "Console control-state simulation (MainScreen::ControlState)\n";

  drive(console, "Normal therapy cycle",
    {Event::CatheterConnected, Event::Prepare, Event::ChargeComplete,
     Event::Confirm, Event::Deliver, Event::AblateComplete,
     Event::CooldownStart, Event::CooldownComplete});

  drive(console, "Pace, then abort back to charged",
    {Event::CatheterConnected, Event::Prepare, Event::ChargeComplete,
     Event::Pace, Event::Abort});

  drive(console, "Catheter drops out mid-charge",
    {Event::CatheterConnected, Event::Prepare, Event::CatheterDisconnected});

  drive(console, "Invalid event ignored: deliver before arming",
    {Event::CatheterConnected, Event::Prepare, Event::ChargeComplete,
     Event::Deliver});

  drive(console, "Fault during delivery, clear, then reconnect",
    {Event::CatheterConnected, Event::Prepare, Event::ChargeComplete,
     Event::Confirm, Event::Deliver, Event::Fault, Event::ClearError,
     Event::CatheterConnected});

  // Guard demo: Prepare is blocked (ignored) while pacing is disabled, then
  // allowed once it is enabled.
  pacingEnabled = false;
  drive(console, "Prepare blocked while pacing disabled",
    {Event::CatheterConnected, Event::Prepare});

  pacingEnabled = true;
  drive(console, "Prepare allowed once pacing enabled",
    {Event::CatheterConnected, Event::Prepare, Event::ChargeComplete});

  drive(console, "Repeated fault while already in ERROR is logged",
    {Event::CatheterConnected, Event::Fault, Event::Fault, Event::ClearError});

  return 0;
}
