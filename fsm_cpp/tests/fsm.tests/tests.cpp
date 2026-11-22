#include "CppUnitTest.h"

#include <string>
#include <string_view>
#include <vector>

import fsm;

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

namespace {

enum class parity { even, odd };

// DFA over {'0','1'} accepting words with an even number of 1s.
fsm::dfa<parity, char> parity_machine() {
  fsm::dfa<parity, char> m;
  m.start(parity::even)
      .accept(parity::even)
      .on(parity::even, '0', parity::even)
      .on(parity::even, '1', parity::odd)
      .on(parity::odd, '0', parity::odd)
      .on(parity::odd, '1', parity::even);
  return m;
}

}  // namespace

namespace fsm_tests {

TEST_CLASS(AcceptanceTests) {
 public:
  TEST_METHOD(EmptyWordIsAccepted) {
    Assert::IsTrue(parity_machine().accepts(std::string_view{""}));
  }

  TEST_METHOD(EvenOnesAccepted) {
    auto m = parity_machine();
    Assert::IsTrue(m.accepts(std::string_view{"11"}));
    Assert::IsTrue(m.accepts(std::string_view{"1010"}));
    Assert::IsTrue(m.accepts(std::string_view{"101"}));  // two 1s
  }

  TEST_METHOD(OddOnesRejected) {
    auto m = parity_machine();
    Assert::IsFalse(m.accepts(std::string_view{"1"}));
    Assert::IsFalse(m.accepts(std::string_view{"111"}));  // three 1s
  }

  TEST_METHOD(UndefinedSymbolRejects) {
    // '2' has no transition defined -> word rejected.
    Assert::IsFalse(parity_machine().accepts(std::string_view{"102"}));
  }

  TEST_METHOD(AcceptsIsSideEffectFree) {
    auto m = parity_machine();
    m.accepts(std::string_view{"111"});
    // No reset()/step() called, so the live machine is untouched.
    Assert::IsFalse(m.live());
  }
};

TEST_CLASS(ExecutionTests) {
 public:
  TEST_METHOD(ResetGoesToStartAndIsLive) {
    auto m = parity_machine();
    m.reset();
    Assert::IsTrue(m.live());
    Assert::IsTrue(m.current() == parity::even);
    Assert::IsTrue(m.accepted());
  }

  TEST_METHOD(StepTracksCurrentState) {
    auto m = parity_machine();
    m.reset();
    Assert::IsTrue(m.step('1'));
    Assert::IsTrue(m.current() == parity::odd);
    Assert::IsFalse(m.accepted());
    Assert::IsTrue(m.step('1'));
    Assert::IsTrue(m.current() == parity::even);
    Assert::IsTrue(m.accepted());
  }

  TEST_METHOD(UndefinedTransitionKillsMachine) {
    auto m = parity_machine();
    m.reset();
    Assert::IsFalse(m.step('x'));
    Assert::IsFalse(m.live());
    Assert::IsFalse(m.step('0'));  // stays dead
  }

  TEST_METHOD(RunStopsAtFirstUndefinedSymbol) {
    auto m = parity_machine();
    m.reset();
    Assert::IsFalse(m.run(std::string_view{"10x1"}));
    Assert::IsFalse(m.live());
  }
};

TEST_CLASS(UndefinedPolicyTests) {
 public:
  TEST_METHOD(IgnoreKeepsMachineLiveAndInPlace) {
    auto m = parity_machine();
    m.undefined(fsm::on_undefined::ignore);
    m.reset();
    Assert::IsFalse(m.step('x'));          // no transition for 'x'
    Assert::IsTrue(m.live());              // but still live
    Assert::IsTrue(m.current() == parity::even);  // stayed put
    Assert::IsTrue(m.step('1'));           // and keeps working
    Assert::IsTrue(m.current() == parity::odd);
  }

  TEST_METHOD(IgnoreRunConsumesWholeSequence) {
    auto m = parity_machine();
    m.undefined(fsm::on_undefined::ignore);
    m.reset();
    // 'x' is skipped; the three 1s still flip parity to odd.
    Assert::IsFalse(m.run(std::string_view{"1x11"}));  // not all defined
    Assert::IsTrue(m.live());
    Assert::IsTrue(m.current() == parity::odd);
  }
};

TEST_CLASS(GuardTests) {
 public:
  TEST_METHOD(GuardBlocksTransitionWhenFalse) {
    bool allow = false;
    fsm::dfa<int, char> m;
    m.start(0).accept(1).on(0, 'g', 1, [&allow] { return allow; });
    m.undefined(fsm::on_undefined::ignore);
    m.reset();
    Assert::IsFalse(m.step('g'));  // guard false -> no transition
    Assert::IsTrue(m.current() == 0);
    allow = true;
    Assert::IsTrue(m.step('g'));   // guard true -> fires
    Assert::IsTrue(m.current() == 1);
  }

  TEST_METHOD(GuardAffectsAcceptsQuery) {
    bool allow = false;
    fsm::dfa<int, char> m;
    m.start(0).accept(1).on(0, 'g', 1, [&allow] { return allow; });
    Assert::IsFalse(m.accepts(std::string_view{"g"}));
    allow = true;
    Assert::IsTrue(m.accepts(std::string_view{"g"}));
  }
};

TEST_CLASS(ReactiveTests) {
 public:
  TEST_METHOD(ObserverFiresOncePerTransition) {
    auto m = parity_machine();
    int count = 0;
    parity last_to = parity::even;
    m.subscribe([&](const fsm::transition<parity, char>& t) {
      ++count;
      last_to = t.to;
    });
    m.reset();
    m.run(std::string_view{"110"});
    Assert::AreEqual(3, count);
    Assert::IsTrue(last_to == parity::even);
  }

  TEST_METHOD(ObserverNotFiredByPureAccepts) {
    auto m = parity_machine();
    int count = 0;
    m.subscribe([&](const auto&) { ++count; });
    m.accepts(std::string_view{"111"});
    Assert::AreEqual(0, count);
  }
};

TEST_CLASS(EntryActionTests) {
 public:
  TEST_METHOD(EntryFiresOnResetThenEachTransition) {
    auto m = parity_machine();
    int even = 0, odd = 0;
    m.on_entry(parity::even, [&] { ++even; });
    m.on_entry(parity::odd, [&] { ++odd; });
    m.reset();  // start state 'even' becomes active
    Assert::AreEqual(1, even);
    Assert::AreEqual(0, odd);
    m.run(std::string_view{"11"});  // even->odd->even
    Assert::AreEqual(2, even);
    Assert::AreEqual(1, odd);
  }

  TEST_METHOD(EntryFiresOnEachReEntryIncludingSelfLoops) {
    auto m = parity_machine();
    int odd = 0;
    m.on_entry(parity::odd, [&] { ++odd; });
    m.reset();
    m.run(std::string_view{"100"});  // ->odd, odd->odd, odd->odd
    Assert::AreEqual(3, odd);
  }

  TEST_METHOD(EntryNotFiredByPureAccepts) {
    auto m = parity_machine();
    int count = 0;
    m.on_entry(parity::even, [&] { ++count; });
    m.on_entry(parity::odd, [&] { ++count; });
    m.accepts(std::string_view{"101"});
    Assert::AreEqual(0, count);
  }
};

TEST_CLASS(ExitActionTests) {
 public:
  TEST_METHOD(ExitFiresOnEachTransitionButNotOnReset) {
    auto m = parity_machine();
    int evenExit = 0, oddExit = 0;
    m.on_exit(parity::even, [&] { ++evenExit; });
    m.on_exit(parity::odd, [&] { ++oddExit; });
    m.reset();  // entering the start state is NOT an exit
    Assert::AreEqual(0, evenExit);
    Assert::AreEqual(0, oddExit);
    m.run(std::string_view{"11"});  // even->odd (exit even), odd->even (exit odd)
    Assert::AreEqual(1, evenExit);
    Assert::AreEqual(1, oddExit);
  }

  TEST_METHOD(ExitFiresOnEachSelfLoop) {
    auto m = parity_machine();
    int oddExit = 0;
    m.on_exit(parity::odd, [&] { ++oddExit; });
    m.reset();
    m.run(std::string_view{"100"});  // ->odd, odd->odd, odd->odd: leaves odd twice
    Assert::AreEqual(2, oddExit);
  }

  TEST_METHOD(ExitNotFiredByGuardRejectOrUndefined) {
    bool allow = false;
    fsm::dfa<int, char> m;
    m.start(0).on(0, 'g', 1, [&allow] { return allow; });
    m.undefined(fsm::on_undefined::ignore);
    int exit0 = 0;
    m.on_exit(0, [&] { ++exit0; });
    m.reset();
    Assert::IsFalse(m.step('g'));  // guard false -> no transition -> no exit
    Assert::AreEqual(0, exit0);
    Assert::IsFalse(m.step('x'));  // undefined symbol -> no exit
    Assert::AreEqual(0, exit0);
    allow = true;
    Assert::IsTrue(m.step('g'));   // real transition -> exit fires
    Assert::AreEqual(1, exit0);
  }

  TEST_METHOD(ExitNotFiredByPureAccepts) {
    auto m = parity_machine();
    int count = 0;
    m.on_exit(parity::even, [&] { ++count; });
    m.on_exit(parity::odd, [&] { ++count; });
    m.accepts(std::string_view{"101"});
    Assert::AreEqual(0, count);
  }

  TEST_METHOD(ExitFiresBeforeObserverThenEntry) {
    auto m = parity_machine();
    std::vector<std::string> order;
    m.on_exit(parity::even, [&] { order.push_back("exit"); });
    m.subscribe([&](const auto&) { order.push_back("observer"); });
    m.on_entry(parity::odd, [&] { order.push_back("entry"); });
    m.reset();      // start-state entry; exit does not fire here
    order.clear();  // measure only the transition below
    m.step('1');    // even->odd: exit(even) -> observer -> entry(odd)
    Assert::AreEqual(static_cast<size_t>(3), order.size());
    Assert::IsTrue(order[0] == "exit");
    Assert::IsTrue(order[1] == "observer");
    Assert::IsTrue(order[2] == "entry");
  }
};

TEST_CLASS(QueryTests) {
 public:
  TEST_METHOD(CanReflectsDefinedAndUndefinedSymbols) {
    auto m = parity_machine();
    m.reset();
    Assert::IsTrue(m.can('0'));
    Assert::IsTrue(m.can('1'));
    Assert::IsFalse(m.can('x'));  // no edge from 'even'
  }

  TEST_METHOD(CanIsFalseWhenNotLive) {
    auto m = parity_machine();
    Assert::IsFalse(m.can('0'));  // not reset yet -> not live
    m.reset();
    m.step('x');                  // default halt policy kills the machine
    Assert::IsFalse(m.live());
    Assert::IsFalse(m.can('0'));  // dead machine offers nothing
  }

  TEST_METHOD(CanRespectsGuards) {
    bool allow = false;
    fsm::dfa<int, char> m;
    m.start(0).on(0, 'g', 1, [&allow] { return allow; });
    m.reset();
    Assert::IsFalse(m.can('g'));  // guard currently false
    allow = true;
    Assert::IsTrue(m.can('g'));   // guard now passes
  }

  TEST_METHOD(AvailableListsFirableSymbolsInAscendingOrder) {
    fsm::dfa<int, char> m;
    m.start(0).on(0, 'c', 1).on(0, 'a', 1).on(0, 'b', 1);
    m.reset();
    auto avail = m.available();
    Assert::AreEqual(static_cast<size_t>(3), avail.size());
    Assert::IsTrue(avail[0] == 'a');  // std::map keeps symbols ordered
    Assert::IsTrue(avail[1] == 'b');
    Assert::IsTrue(avail[2] == 'c');
  }

  TEST_METHOD(AvailableExcludesGuardBlockedAndIsEmptyWhenNotLive) {
    bool allow = false;
    fsm::dfa<int, char> m;
    m.start(0).on(0, 'x', 1).on(0, 'g', 2, [&allow] { return allow; });
    m.reset();
    auto a1 = m.available();
    Assert::AreEqual(static_cast<size_t>(1), a1.size());  // 'g' guard blocks it
    Assert::IsTrue(a1[0] == 'x');
    allow = true;
    Assert::AreEqual(static_cast<size_t>(2), m.available().size());  // 'g' now firable

    fsm::dfa<int, char> dead;  // never started -> not live
    Assert::IsTrue(dead.available().empty());
  }
};

TEST_CLASS(GenericityTests) {
 public:
  // Prove the template works over unrelated State/Symbol types: int states
  // and int symbols. Machine accepts sequences summing (mod) to state 0 via a
  // tiny mod-3 counter driven by +1 steps.
  TEST_METHOD(IntStatesAndSymbols) {
    fsm::dfa<int, int> m;
    m.start(0).accept(0).on(0, 1, 1).on(1, 1, 2).on(2, 1, 0);
    Assert::IsTrue(m.accepts(std::vector<int>{1, 1, 1}));   // 3 steps -> 0
    Assert::IsFalse(m.accepts(std::vector<int>{1, 1}));     // -> 2
    Assert::IsTrue(m.accepts(std::vector<int>{}));          // start accepts
  }

  TEST_METHOD(StringStatesAndSymbols) {
    fsm::dfa<std::string, std::string> m;
    m.start("locked")
        .accept("open")
        .on("locked", "coin", "open")
        .on("open", "push", "locked");
    Assert::IsTrue(m.accepts(std::vector<std::string>{"coin"}));
    Assert::IsTrue(
        m.accepts(std::vector<std::string>{"coin", "push", "coin"}));
    Assert::IsFalse(m.accepts(std::vector<std::string>{"coin", "push"}));
  }
};

}  // namespace fsm_tests
