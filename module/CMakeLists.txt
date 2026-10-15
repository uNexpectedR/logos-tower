cmake_minimum_required(VERSION 3.14)
project(LogosTowerPlugin LANGUAGES C CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)

logos_module(
    NAME ${MODULE_NAME}
    REP_FILE src/logos_tower.rep
    SOURCES
        src/logos_tower_backend.h
        src/logos_tower_backend.cpp
        src/monocypher.c
        src/monocypher-ed25519.c
    INCLUDE_DIRS
        src
)
