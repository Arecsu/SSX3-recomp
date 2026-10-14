# cmake -DIN=<file.spv> -DOUT=<file.h> -DNAME=<symbol> -P embed_spv.cmake
file(READ "${IN}" hex HEX)
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
string(LENGTH "${hex}" hexlen)
math(EXPR len "${hexlen} / 2")
file(WRITE "${OUT}"
    "static const unsigned char ${NAME}[] __attribute__((aligned(4))) = {${bytes}};\n"
    "static const unsigned long ${NAME}_len = ${len};\n")
