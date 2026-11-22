cmake_minimum_required(VERSION 3.21)

project(fsm_visualizer VERSION 1.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Quick3D)  # Quick3D: Phase 0 3D spike

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(appFsmVisualizer
    main.cpp
    FsmViewModel.cpp
    FsmViewModel.h
    FsmDefinition.cpp
    FsmDefinition.h
    FsmMachine.cpp
    FsmMachine.h
    FsmFileStore.cpp
    FsmFileStore.h
    FsmCodecs.cpp
    FsmCodecs.h
)

# GUI app: link as a Windows GUI subsystem executable so no console window
# opens alongside it (Qt's entry-point wrapper still calls main()).
set_target_properties(appFsmVisualizer PROPERTIES WIN32_EXECUTABLE TRUE)

# Embed the application icon into the Windows executable (shown in Explorer,
# the taskbar and Alt-Tab). windres resolves appicon.ico via the target's
# include dirs below.
if (WIN32)
    enable_language(RC)
    target_sources(appFsmVisualizer PRIVATE appicon.rc)
endif()

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# All module QML lives under qml/; this policy auto-generates the qmldir for
# that subdirectory so the types resolve without a QTP0004 warning.
qt_policy(SET QTP0004 NEW)

qt_add_qml_module(appFsmVisualizer
    URI FsmVis
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/TitleBar.qml
        qml/Dialogs.qml
        qml/GraphView.qml
        qml/CanvasPanes.qml
        qml/ActionGlyph.qml
        qml/GraphView3D.qml
        qml/Controls2D.qml
        qml/Controls3D.qml
    RESOURCES
        appicon.png
)

# Present the .qml files under their own "Qmls" node in IDEs that honour
# source_group (e.g. Visual Studio), alongside the auto-generated "Header Files"
# and "Source Files" groups. This is an IDE-only grouping; nothing moves on disk.
source_group("Qmls" FILES
    qml/Main.qml
    qml/Theme.qml
    qml/TitleBar.qml
    qml/Dialogs.qml
    qml/GraphView.qml
    qml/CanvasPanes.qml
    qml/ActionGlyph.qml
    qml/GraphView3D.qml
    qml/Controls2D.qml
    qml/Controls3D.qml
)

# Reuse the canonical header-only DFA twin that sits next to the C++20 module.
# fsm.hpp is GENERATED from fsm.ixx (the source of truth) by scripts/gen_fsm_hpp.py.
target_include_directories(appFsmVisualizer PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/fsm
)
target_link_libraries(appFsmVisualizer PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Quick3D)

# Make the project version available to the app (shown after the title) so it
# stays single-sourced from project(... VERSION ...).
target_compile_definitions(appFsmVisualizer PRIVATE APP_VERSION="${PROJECT_VERSION}")

# Guard against drift: fail the build if fsm.hpp wasn't regenerated after fsm.ixx
# changed. Skipped (with a notice) when no Python interpreter is available.
find_package(Python3 COMPONENTS Interpreter QUIET)
if (Python3_FOUND)
    add_custom_target(fsm_header_sync_check ALL
        COMMAND ${Python3_EXECUTABLE} -I
                ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/gen_fsm_hpp.py --check
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/..
        COMMENT "Checking src/fsm/fsm.hpp is in sync with fsm.ixx"
        VERBATIM)
    add_dependencies(appFsmVisualizer fsm_header_sync_check)
else()
    message(STATUS "Python3 not found; skipping the fsm.hpp<->fsm.ixx sync check")
endif()
