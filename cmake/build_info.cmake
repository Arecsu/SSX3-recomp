# Writes build_info.h (SSX3_BUILD_COMMIT, SSX3_BUILD_DATE) for the session
# log's header -- from git when the source has it, else from the
# BUILD_INFO file scripts/sync-windows.sh leaves in the Windows copy.
# configure_file rewrites the header only when it changes.
set(COMMIT "unknown")
set(DATE "")
if(EXISTS "${SRC}/.git")
    execute_process(COMMAND git -C "${SRC}" describe --always --dirty --abbrev=7
                    OUTPUT_VARIABLE COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    execute_process(COMMAND git -C "${SRC}" log -1 --format=%cs
                    OUTPUT_VARIABLE DATE OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
elseif(EXISTS "${SRC}/BUILD_INFO")
    file(STRINGS "${SRC}/BUILD_INFO" lines)
    list(LENGTH lines n)
    if(n GREATER 0)
        list(GET lines 0 COMMIT)
    endif()
    if(n GREATER 1)
        list(GET lines 1 DATE)
    endif()
endif()
if(NOT COMMIT)
    set(COMMIT "unknown")
endif()
file(WRITE "${OUT}.tmp" "#define SSX3_BUILD_COMMIT \"${COMMIT}\"\n#define SSX3_BUILD_DATE \"${DATE}\"\n")
configure_file("${OUT}.tmp" "${OUT}" COPYONLY)
