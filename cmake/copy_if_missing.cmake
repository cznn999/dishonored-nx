# cmake -DSRC=<file> -DDST=<file> -P copy_if_missing.cmake
# Copies SRC to DST only when DST does not exist yet (the copy next to the exe is the user's to edit).
if(NOT EXISTS "${DST}")
    configure_file("${SRC}" "${DST}" COPYONLY)
    message(STATUS "Wrote ${DST}")
endif()
