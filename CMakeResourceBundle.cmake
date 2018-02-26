# This is free and unencumbered software released into the public domain.

include(CMakeParseArguments)

#[=============================================================================[
CMakeResourceBundle

.. command:: generate_resource_bundle

  The ``generate_resource_bundle()`` function generates a C source file with
  a hexadecimal representation of any binary data.

      generate_resource_bundle(
        TARGET app-scripts
        RESOURCES
          app/main.lua
          app/util/sum.lua
      )

  The generated source file can then be embedded by libraries or executables to
  have direct access to the resources at runtime without referencing the
  filesystem.

      embed_resource_bundle(
        TARGET app
        BUNDLE app-scripts
      )

  This operation is useful for embedding any form of resources into a binary:
  scripts, images, sound files, etc.

  **Options:**

  ``TARGET <name>``
  The name of the target that will contain the resource bundle. You will later
  use this to embed the bundle into the destination target (like an executable.)

  ``RESOURCES <files...>``
  List of files the bundle should contain. The filename is vital since the
  symbols will be generated after the filenames according to the following
  rules:

  - slashes (/ and \), spaces, dashes (-) and dots are converted to _
  - file extension is kept as a suffix
  - uppercase

  So for a file at "scripts/init.lua", the symbols will be:

      unsigned char SCRIPTS_INIT_LUA[];
      unsigned int  SCRIPTS_INIT_LUA_SIZE;

  ``PREFIX <id>``
  Identifier to prefix all symbols with. Defaults to none.

  ``SUFFIX <id>``
  Identifier to suffix all symbols with. Defaults to none.
#]=============================================================================]
function(generate_resource_bundle)
  cmake_parse_arguments(GENERATE_RESOURCE_BUNDLE
    ""                        # switches
    "TARGET;PREFIX;SUFFIX"    # one value args
    "RESOURCES"               # multi value args
    ${ARGN}
  )

  set(target        ${GENERATE_RESOURCE_BUNDLE_TARGET})
  set(input_file    ${CMAKE_CURRENT_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/${target}.input)
  set(output_file   ${CMAKE_CURRENT_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/script-bundle.c)
  set(resource_list "")

  # stage input file containing list of scripts for processing
  string(REPLACE ";" "\n" resource_list "${GENERATE_RESOURCE_BUNDLE_RESOURCES}")
  file(WRITE ${input_file} "${resource_list}")

  add_custom_command(
    OUTPUT "${output_file}"
    COMMAND ${CMAKE_COMMAND}
      -D_CRB_INPUT:string=${input_file}
      -D_CRB_OUTPUT:string=${output_file}
      -D_CRB_PREFIX:string=${GENERATE_RESOURCE_BUNDLE_PREFIX}
      -D_CRB_SUFFIX:string=${GENERATE_RESOURCE_BUNDLE_SUFFIX}
      -D_CRB_DO_GENERATE:bool=ON
      -P ${_CRB_SCRIPT_PATH}
    DEPENDS ${GENERATE_RESOURCE_BUNDLE_RESOURCES}
            ${_CRB_SCRIPT_PATH}
            ${CMAKE_CURRENT_LIST_FILE}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Generating resource bundle \"${target}\""
    VERBATIM
  )

  set_source_files_properties(${output_file} PROPERTIES GENERATED TRUE)

  set_property(
    DIRECTORY
      "${CMAKE_CURRENT_SOURCE_DIR}"
    APPEND PROPERTY
      ADDITIONAL_MAKE_CLEAN_FILES ${output_file}
  )

  add_library(${target} OBJECT ${output_file})
endfunction()

function(embed_resource_bundle)
  cmake_parse_arguments(EMBED_RESOURCE_BUNDLE "" "BUNDLE;TARGET" "" ${ARGN})

  target_sources(${EMBED_RESOURCE_BUNDLE_TARGET} PRIVATE
    $<TARGET_OBJECTS:${EMBED_RESOURCE_BUNDLE_BUNDLE}>
  )

  if (UNIX)
    target_link_libraries(${EMBED_RESOURCE_BUNDLE_TARGET} PRIVATE -Wl,-E)
  endif()
endfunction()

function(_crb_generate_resource_bundle)
  # Credit: https://gist.github.com/sivachandran/3a0de157dccef822a230
  # Author: Sivachandran <sivachandran.p@gmail.com>
  #
  # Function to wrap a given string into multiple lines at the given column position.
  # Parameters:
  #   VARIABLE    - The name of the CMake variable holding the string.
  #   AT_COLUMN   - The column position at which string will be wrapped.
  function(wrap_string)
    set(oneValueArgs VARIABLE AT_COLUMN)
    cmake_parse_arguments(WRAP_STRING "${options}" "${oneValueArgs}" "" ${ARGN})

    string(LENGTH ${${WRAP_STRING_VARIABLE}} stringLength)
    math(EXPR offset "0")

    while(stringLength GREATER 0)

      if(stringLength GREATER ${WRAP_STRING_AT_COLUMN})
        math(EXPR length "${WRAP_STRING_AT_COLUMN}")
      else()
        math(EXPR length "${stringLength}")
      endif()

      string(SUBSTRING ${${WRAP_STRING_VARIABLE}} ${offset} ${length} line)
      set(lines "${lines}\n${line}")

      math(EXPR stringLength "${stringLength} - ${length}")
      math(EXPR offset "${offset} + ${length}")
    endwhile()

    set(${WRAP_STRING_VARIABLE} "${lines}" PARENT_SCOPE)
  endfunction()

  # Credit: https://gist.github.com/sivachandran/3a0de157dccef822a230
  # Author: Sivachandran <sivachandran.p@gmail.com>
  #
  # Function to embed contents of a file as byte array in C/C++ header file(.h). The header file
  # will contain a byte array and integer variable holding the size of the array.
  # Parameters
  #   SOURCE_FILE     - The path of source file whose contents will be embedded in the header file.
  #   VARIABLE_NAME   - The name of the variable for the byte array. The string "_SIZE" will be append
  #                     to this name and will be used a variable name for size variable.
  #   HEADER_FILE     - The path of header file.
  #   APPEND          - If specified appends to the header file instead of overwriting it
  #   NULL_TERMINATE  - If specified a null byte(zero) will be append to the byte array. This will be
  #                     useful if the source file is a text file and we want to use the file contents
  #                     as string. But the size variable holds size of the byte array without this
  #                     null byte.
  # Usage:
  #   bin2h(SOURCE_FILE "Logo.png" HEADER_FILE "Logo.h" VARIABLE_NAME "LOGO_PNG")
  #
  # Modifications:
  #
  # - Each identifier for a resource (buffer and bufsz) are followed by two magic
  #   incantations to force the symbols not to be undefined when linking
  #   statically through the use of the FORCE_REF_SYMBOL macro which is
  #   expected to have been injected by ./apply.cmake
  function(bin2h)
    set(options APPEND NULL_TERMINATE)
    set(oneValueArgs SOURCE_FILE VARIABLE_NAME HEADER_FILE)
    cmake_parse_arguments(BIN2H "${options}" "${oneValueArgs}" "" ${ARGN})

    # reads source file contents as hex string
    file(READ ${BIN2H_SOURCE_FILE} hexString HEX)
    string(LENGTH ${hexString} hexStringLength)

    # appends null byte if asked
    if(BIN2H_NULL_TERMINATE)
      set(hexString "${hexString}00")
    endif()

    # wraps the hex string into multiple lines at column 32(i.e. 16 bytes per line)
    wrap_string(VARIABLE hexString AT_COLUMN 32)
    math(EXPR arraySize "${hexStringLength} / 2")

    # adds '0x' prefix and comma suffix before and after every byte respectively
    string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1, " arrayValues ${hexString})
    # removes trailing comma
    string(REGEX REPLACE ", $" "" arrayValues ${arrayValues})

    # converts the variable name into proper C identifier
    string(MAKE_C_IDENTIFIER "${BIN2H_VARIABLE_NAME}" BIN2H_VARIABLE_NAME)
    string(TOUPPER "${BIN2H_VARIABLE_NAME}" BIN2H_VARIABLE_NAME)

    # declares byte array and the length variables
    set(arrayDefinition             "const unsigned char ${BIN2H_VARIABLE_NAME}[] = { ${arrayValues} };")
    set(arraySizeDefinition         "const unsigned int  ${BIN2H_VARIABLE_NAME}_SIZE = ${arraySize};")

    # <mods: 20171208>
    set(forceArrayDefinition        "FORCE_REF_SYMBOL(${BIN2H_VARIABLE_NAME})")
    set(forceArraySizeDefinition    "FORCE_REF_SYMBOL(${BIN2H_VARIABLE_NAME}_SIZE)")

    set(declarations "${arraySizeDefinition}\n${arrayDefinition}\n\n${forceArrayDefinition}\n${forceArraySizeDefinition}\n\n")
    # </mods>

    if(BIN2H_APPEND)
      file(APPEND ${BIN2H_HEADER_FILE} "${declarations}")
    else()
      file(WRITE ${BIN2H_HEADER_FILE} "${declarations}")
    endif()
  endfunction()

  # @private
  #
  # Patch for Visual Studio linker to keep all (seemingly) unused symbols in the
  # target.
  #
  # Credit: https://stackoverflow.com/a/2993476
  # Credit: https://pocoproject.org/blog/?p=741
  # Credit: https://social.msdn.microsoft.com/Forums/vstudio/en-US/2aa2e1b7-6677-4986-99cc-62f463c94ef3/linkexe-bug-optnoref-option-doesnt-work?forum=vclanguage
  set(_CRB_MSVC_PATCH "                                                           \n
#if defined(_WIN32)                                                               \n
# if defined(_WIN64)                                                              \n
#  define FORCE_REF_SYMBOL(x) __pragma(comment (linker, \"/export:\" #x))         \n
# else                                                                            \n
#  define FORCE_REF_SYMBOL(x) __pragma(comment (linker, \"/export:_\" #x))        \n
# endif                                                                           \n
#else                                                                             \n
# define FORCE_REF_SYMBOL(x)                                                      \n
#endif                                                                            \n
  ")

  file(WRITE   ${_CRB_OUTPUT} "${_CRB_MSVC_PATCH}\n")
  file(STRINGS ${_CRB_INPUT}  files)

  foreach(file ${files})
    # replace filename spaces & extension separator for C compatibility
    string(REGEX REPLACE "\\.| |-|/|\\\\" "_" identifier ${file})
    set(fqidentifier "${_CRB_PREFIX}${identifier}${_CRB_SUFFIX}")

    bin2h(
      SOURCE_FILE ${file}
      HEADER_FILE ${_CRB_OUTPUT}
      VARIABLE_NAME ${fqidentifier}
      APPEND
      NULL_TERMINATE
    )
  endforeach()

endfunction()

# @private
set(_CRB_SCRIPT_PATH ${CMAKE_CURRENT_LIST_FILE})

# when invoked by generate_resource_bundle()
if (_CRB_DO_GENERATE)
  _crb_generate_resource_bundle()
endif()