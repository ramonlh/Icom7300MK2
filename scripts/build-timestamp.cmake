string(TIMESTAMP BUILD_TIMESTAMP "%d/%m/%Y %H:%M:%S")
file(WRITE "${OUTPUT_FILE}"
    "#pragma once\n#define APP_BUILD_TIMESTAMP \"${BUILD_TIMESTAMP}\"\n")
