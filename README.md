# CMakeResourceBundle

A CMake script for generating C source files with a hexadecimal representation
of any binary data. The generated source file can then be embedded by libraries
or executables to have direct access to the resources at runtime without
referencing the filesystem.

In such systems, this process may be ideal to embed any form of resources into
a binary: scripts (Lua), images, sound files, etc.

The script was tested on Linux and Windows 10.