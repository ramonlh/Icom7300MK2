cmake_minimum_required(VERSION 3.16)

project(Icom7300Mk2Control
    VERSION 1.2.12
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS
    Quick
    QuickControls2
    SerialPort
    Multimedia
    Network
)

qt_standard_project_setup()

qt_add_executable(Icom7300Mk2Control
    main.cpp
    applicationlauncher.cpp
    applicationlauncher.h
    radiocontroller.cpp
    radiocontroller.h
    morsetrainer.cpp
    morsetrainer.h
    remoteserver.cpp
    remoteserver.h
)

# Refresh the timestamp on every build, including incremental builds.
add_custom_target(build_timestamp
    COMMAND ${CMAKE_COMMAND}
        -DOUTPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/build_timestamp.h
        -P ${CMAKE_CURRENT_SOURCE_DIR}/scripts/build-timestamp.cmake
    BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/build_timestamp.h
    VERBATIM
)
add_dependencies(Icom7300Mk2Control build_timestamp)
target_include_directories(Icom7300Mk2Control PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

qt_add_resources(Icom7300Mk2Control "app_resources"
    PREFIX "/"
    FILES
        Main.qml
        MorseTrainerWindow.qml
        remote/index.html
        icons/icom7300mk2_control_32.png
        icons/icom7300mk2_control_48.png
        icons/icom7300mk2_control_64.png
        icons/icom7300mk2_control_128.png
        icons/icom7300mk2_control_256.png
        icons/icom7300mk2_control_512.png
)

target_link_libraries(Icom7300Mk2Control
    PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::SerialPort
        Qt6::Multimedia
        Qt6::Network
)

set_target_properties(Icom7300Mk2Control PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

option(ICOM_BUILD_TESTS "Build isolated controller tests" OFF)
if(ICOM_BUILD_TESTS)
    enable_testing()
    add_executable(lan_receiver_test
        tests/lan_receiver_test.cpp radiocontroller.cpp radiocontroller.h)
    target_include_directories(lan_receiver_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(lan_receiver_test PRIVATE Qt6::Quick Qt6::SerialPort)
    add_test(NAME lan_receiver COMMAND lan_receiver_test)
endif()


# Instalación opcional para Linux.
# El nombre del .desktop debe coincidir con setDesktopFileName().
if(UNIX AND NOT APPLE)
    install(TARGETS Icom7300Mk2Control
        RUNTIME DESTINATION bin
    )

    install(FILES
        org.icom.Icom7300Mk2Control.desktop
        DESTINATION share/applications
    )

    foreach(icon_size 32 48 64 128 256 512)
        install(FILES
            icons/icom7300mk2_control_${icon_size}.png
            DESTINATION
                share/icons/hicolor/${icon_size}x${icon_size}/apps
            RENAME
                org.icom.Icom7300Mk2Control.png
        )
    endforeach()
endif()
