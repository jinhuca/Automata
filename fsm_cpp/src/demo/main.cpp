// Demo: a generic DFA whose transition stream is exposed as an RxCpp
// observable (Reactive Extensions for C++). The machine recognises binary
// strings containing an even number of 1s.

#include <iostream>
#include <string>
#include <string_view>

#include <rxcpp/rx.hpp>

import fsm;

namespace {

  // State of the parity DFA: even or odd number of 1s seen so far.
  enum class parity { even, odd };

  // Human-readable label for a parity state.
  std::string_view name(parity p) { return p == parity::even ? "even" : "odd"; }

  // Build the "even number of 1s" machine over the alphabet {'0','1'}.
  fsm::dfa<parity, char> make_parity_machine() {
    fsm::dfa<parity, char> m;
    m.start(parity::even)
      .accept(parity::even)
      .on(parity::even, '0', parity::even)
      .on(parity::even, '1', parity::odd)
      .on(parity::odd, '0', parity::odd)
      .on(parity::odd, '1', parity::even);
    return m;
  }

  // Runs one input word through the parity machine, wiring up per-state
  // simulation actions and an RxCpp transition stream, then reports acceptance.
  void run_reactively(std::string_view word) {
    auto machine = make_parity_machine();

    // Per-state entry actions: fire whenever the machine enters a state
    // (including the start state at reset), tallying entries and standing in for
    // a per-state side effect.
    int even_entries = 0, odd_entries = 0;
    machine.on_entry(parity::even, [&] {
      ++even_entries;
      std::cout << "    [sim] even state: parity OK (indicator green)\n";
    });
    machine.on_entry(parity::odd, [&] {
      ++odd_entries;
      std::cout << "    [sim] odd state: parity ODD (indicator red)\n";
    });

    // Bridge the DFA's push-based hook into an RxCpp subject so transitions
    // become a first-class observable we can compose with Rx operators.
    rxcpp::subjects::subject<fsm::transition<parity, char>> subject;
    auto bus = subject.get_subscriber();
    machine.subscribe([&bus](const fsm::transition<parity, char>& t) {
      bus.on_next(t);
    });

    // Reactive pipeline: report only the transitions that actually flip parity.
    subject.get_observable()
      .filter([](const auto& t) { return t.from != t.to; })
      .subscribe([](const auto& t) {
      std::cout << "    [rx] '" << t.symbol << "' flipped " << name(t.from)
        << " -> " << name(t.to) << '\n';
    });

    machine.reset();
    machine.run(word);
    bus.on_completed();

    std::cout << "  \"" << word << "\" -> final=" << name(machine.current())
      << (machine.accepted() ? "  ACCEPT" : "  reject")
      << "  (entries: even=" << even_entries << ", odd=" << odd_entries
      << ")\n";
  }

}  // namespace

int main() {
  std::cout << "Generic DFA demo: even number of 1s\n\n";
  for(std::string_view word : {"", "11", "1", "1010", "101"}) {
    run_reactively(word);
    std::cout << '\n';
  }
  return 0;
}
