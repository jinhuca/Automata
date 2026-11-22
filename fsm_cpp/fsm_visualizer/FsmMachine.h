#pragma once

#include <QString>
#include <QStringList>

#include <functional>
#include <string>

#include "FsmDefinition.h"
#include "fsm.hpp"

// Wraps a generic fsm::dfa<std::string,std::string> and the live run state it
// produces (current state, acceptance, available symbols, the visited path and
// the transition that fired most recently). Plain C++ — no QObject and no timer;
// run *pacing* (the animation) is a UI concern that lives in FsmViewModel. A log
// sink callback routes the DFA's transition trace and "ignored" notices back to
// the view-model's activity log.
class FsmMachine {
 public:
    using Logger = std::function<void(const QString&)>;
    void setLogger(Logger sink) { m_log = std::move(sink); }

    // (Re)assemble the machine from a parsed definition and reset to s₀.
    void build(const fsmdef::FsmDefinition& def);
    // Apply one symbol; returns true iff a transition fired.
    bool step(const QString& symbol);
    // Return to s₀ (no-op when not built).
    void reset();
    // Forget the machine and all run state (built() becomes false).
    void clear();

    bool built() const { return m_built; }
    QString current() const { return m_current; }
    bool live() const { return m_live; }
    bool accepted() const { return m_accepted; }
    QStringList available() const { return m_available; }
    QStringList path() const { return m_path; }
    QString lastFrom() const { return m_lastFrom; }
    QString lastSymbol() const { return m_lastSymbol; }
    QString lastTo() const { return m_lastTo; }

 private:
    // Pull current/live/accepted/available out of the DFA into the cached fields.
    void refresh();

    fsm::dfa<std::string, std::string> m_dfa;
    bool m_built = false;
    QString m_current;
    bool m_live = false;
    bool m_accepted = false;
    QStringList m_available;
    QStringList m_path;                          // states visited since last reset
    QString m_lastFrom, m_lastSymbol, m_lastTo;  // most recent fired transition
    Logger m_log;
};
