# cmake -DIN=<file.spv> -DOUT=<file.h> -DNAME=<symbol> -P embed_spv.cmake
file(READ "${IN}" hex HEX)
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
string(LENGTH "${hex}" hexlen)
math(EXPR len "${hexlen} / 2")
file(WRITE "${OUT}"
    "#ifdef _MSC_VER\n__declspec(align(4))\n#endif\n"
    "static const unsigned char ${NAME}[]\n#ifndef _MSC_VER\n__attribute__((aligned(4)))\n#endif\n= {${bytes}};\n"
    "static const unsigned long ${NAME}_len = ${len};\n")
