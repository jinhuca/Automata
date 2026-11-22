#pragma once

#include <QMap>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <string>
#include <vector>

// The canonical FSM definition model plus the text parser/validator that
// produces it. Pure (QString-only, no QObject / no fsm::dfa / no QSettings), so
// it is unit-testable in isolation. FsmViewModel orchestrates it; FsmMachine and
// FsmCodecs consume the resulting model.
namespace fsmdef {

// One transition as plain data (shared by the machine and the codecs).
struct Transition {
    std::string from, sym, to;
};

// A parsed, validated definition: symbols Σ, states S, transitions δ, initial
// state s₀, accepting states F.
struct FsmDefinition {
    QStringList states, symbols, accept;
    QString initial;
    std::vector<Transition> tr;  // typed transitions, in input order
    QVariantList transitions;    // QML-facing mirror: [{from, symbol, to}, ...]
    // Per-state entry/exit action text (UML-style). Only states with a non-empty
    // action appear. entryActions/exitActions are QML-facing mirrors of the same.
    QMap<QString, QString> entry, exit;
    QVariantMap entryActions, exitActions;
};

// Outcome of a parse: the (possibly augmented) definition, non-fatal warnings
// (duplicates, inferred/undeclared names, malformed lines, nondeterminism), and
// a fatal error that blocks building the machine (empty when the parse is OK).
struct ParseResult {
    FsmDefinition def;
    QStringList warnings;
    QString error;
};

// Split a comma/newline-separated list into trimmed, non-empty tokens.
QStringList splitCsv(const QString& s);

// Parse the five form fields. transitionsText is a list of "from, symbol, to"
// triples separated by ';' or newlines. Undeclared states/symbols are inferred
// (with a warning); a redefined (from, symbol) keeps the last target (with a
// warning); malformed/empty lines are skipped (with a warning).
// actionsText is a list of "state : entry : exit" lines (either action may be
// blank); an action naming an unknown state is dropped with a warning.
ParseResult parseDefinition(const QString& symbolsCsv, const QString& statesCsv,
                            const QString& transitionsText, const QString& initial,
                            const QString& acceptCsv, const QString& actionsText);

}  // namespace fsmdef
