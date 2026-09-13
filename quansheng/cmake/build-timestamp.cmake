string(TIMESTAMP QDOCK_BUILD_TIMESTAMP "%d/%m/%Y %H:%M:%S")
file(WRITE "${OUTPUT_FILE}"
    "#pragma once\n#define QDOCK_BUILD_TIMESTAMP \"${QDOCK_BUILD_TIMESTAMP}\"\n")
