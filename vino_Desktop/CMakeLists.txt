cmake_minimum_required(VERSION 3.20)

project(vino_Desktop LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

find_package(Threads REQUIRED)

add_library(vino_desktop_core
    src/core/Blueprint.cpp
    src/core/DeviceRegistry.cpp
    src/core/RuntimePaths.cpp
    src/network/BatchGateway.cpp
    src/network/Controller.cpp
    src/network/PostGateway.cpp
    src/protocol/MiniJson.cpp
    src/protocol/Protocol.cpp
    src/ui/DesktopRuntime.cpp
    src/ui/FuturisticTheme.cpp
)

target_include_directories(vino_desktop_core
    PUBLIC
        include
)

target_link_libraries(vino_desktop_core
    PUBLIC
        Threads::Threads
)

if(WIN32)
    target_link_libraries(vino_desktop_core PRIVATE ws2_32)
endif()

add_executable(vino_desktop_blueprint
    src/main.cpp
)

target_link_libraries(vino_desktop_blueprint PRIVATE vino_desktop_core)

if(APPLE)
    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)

    set(APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/Resources/vino_Desktop.icns")

    add_executable(vino_desktop_app MACOSX_BUNDLE
        src/ui/MacApp.mm
        ${APP_ICON}
    )

    set_target_properties(vino_desktop_app PROPERTIES
        OUTPUT_NAME "vino_Desktop"
        MACOSX_BUNDLE_BUNDLE_NAME "vino Desktop"
        MACOSX_BUNDLE_GUI_IDENTIFIER "cc.vino.desktop"
        MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
        MACOSX_BUNDLE_ICON_FILE "vino_Desktop.icns"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Resources/Info.plist.in"
    )

    set_source_files_properties(${APP_ICON} PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )

    target_include_directories(vino_desktop_app
        PRIVATE
            include
    )

    target_compile_options(vino_desktop_app
        PRIVATE
            -fobjc-arc
    )

    target_link_libraries(vino_desktop_app
        PRIVATE
            vino_desktop_core
            ${COCOA_FRAMEWORK}
            ${QUARTZCORE_FRAMEWORK}
    )
endif()
