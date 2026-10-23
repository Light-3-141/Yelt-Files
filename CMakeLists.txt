cmake_minimum_required(VERSION 3.21)
project(Files VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(appFiles main.cpp)

# every .qml file in this folder becomes a type of the "Files" module
# (file names must start with a capital letter: Main.qml, Themes.qml, ...)
file(GLOB QML_SOURCES CONFIGURE_DEPENDS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} *.qml)
message(STATUS "QML files: ${QML_SOURCES}")

qt_add_qml_module(appFiles
    URI Files
    VERSION 1.0
    QML_FILES ${QML_SOURCES}
    SOURCES filemodel.h filemodel.cpp
)

target_link_libraries(appFiles PRIVATE Qt6::Quick)
