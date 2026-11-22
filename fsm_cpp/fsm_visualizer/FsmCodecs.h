#pragma once

#include <QString>
#include <QVariantMap>

#include "FsmDefinition.h"

// Text codecs for the FSM definition: C++ (fsm::dfa) and Graphviz DOT.
//
// These are pure string<->model transforms with no dependency on FsmViewModel
// or any QObject, so they live in their own translation unit and can be
// unit-tested directly. The view-model's Q_INVOKABLE methods are thin forwards
// onto these. They operate on the shared fsmdef::FsmDefinition model.
namespace fsmcodecs {

// Serialize the definition to compilable C++ that builds an fsm::dfa.
QString exportCpp(const fsmdef::FsmDefinition& def);

// Serialize the definition to a Graphviz DOT digraph.
QString exportDot(const fsmdef::FsmDefinition& def);

// Parse a fsm::dfa C++ snippet into {symbols, states, transitions, initial,
// accept}. Returns an empty map when nothing recognisable is found.
QVariantMap importCpp(const QString& code);

// Parse a Graphviz DOT graph into the same shape. Empty map if nothing matched.
QVariantMap importDot(const QString& code);

}  // namespace fsmcodecs
