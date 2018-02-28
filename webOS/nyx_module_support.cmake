# - Common CMake code for all Open webOS components which build nyx modules
#
# Any Open webOS component whose root CMakeLists.txt is written by us, and
# which creates nyx modules should include this module by observing the usage
# below (they don't need to, but it makes life easier).
#
# Usage:
#
#  include(webOS/webOS)
#  webos_modules_init(...)
#  webos_nyx_module_provider()
#
# Their OE recipe must also contain the following line:
#
#  inherit webos_nyx_module_provider
#
# This module is never directly included by a component's CMake script. It is
# brought into scope via the nyx_module_provider() macro in the main webOS.cmake
# module. This way, methods like webos_build_nyx_module() are only available in
# CMake scripts that have invoked webos_nyx_module_provider().
#

# Copyright (c) 2014-2018 LG Electronics, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# Usage: __nyx_get_pkgconfig_var <Cmake variable name> <pkg-config variable name> <usecache>
#
# Extracts the variable given by nyx_pkgconfig_var from nyx-lib's pkg-config .pc file and
# uses it to set the variable named by ${varname}.
#
# If usecache is truthy, the variable is defined in the CMake cache, otherwise it is set as a
# local variable in the parent's scope.
#
# INTERNAL TO THIS MODULE - DO NOT CALL DIRECTLY
function(__nyx_get_pkgconfig_var varname nyx_pkgconfig_var usecache)
	execute_process(COMMAND ${PKG_CONFIG_EXECUTABLE} --variable=${nyx_pkgconfig_var} nyx
	                OUTPUT_VARIABLE pkgconfig_output
	                RESULT_VARIABLE pkgconfig_failed)

	if(NOT pkgconfig_failed)
		STRING(REGEX REPLACE "(/?\r?\n)+$" "" pkgconfig_output "${pkgconfig_output}")
		if(usecache)
			set(${varname} ${pkgconfig_output} CACHE PATH ${nyx_pkgconfig_var})
		else()
			set(${varname} ${pkgconfig_output} PARENT_SCOPE)
		endif()
	else()
		message(FATAL_ERROR "Error in fetching '${nyx_pkgconfig_var}' from nyx.pc, execute_process() returned ${pkgconfig_failed}")
	endif()
endfunction()

# Usage: _webos_nyx_support_init()
#
# Performs one-off initialization of the module.
#
# This must only be performed once, and is meant to occur from within webOS.cmake
#
# On exit, the following variables have been exported to the caller's scope:
#
#   NYX_MODULES_REQUIRED: guaranteed to exist and be in CMake list form
#   NYX_MODULE_DIR:       Path to the install directory for modules
#   NYX_MODULE_PREFIX:    String to prepend to all shared libraries.
#   NYX_MODULE_SUFFIX:	  File extension (suffix) for installed modules
#   NYX_MODULE_MOCK)DIR:  Path to the install directory for mock modules

#   NYXLIB_INCLUDE_DIRS   Added via include_directories()
#   NYXLIB_LDFLAGS        Linker flags (added in webos_build_nyx_module())
#   NYXLIB_CFLAGS_OTHER   Compiler flags (added with webos_add_compiler_flags)
#
macro(_webos_nyx_support_init)
	if(DEFINED __NYX_MODULE_INITIALIZED)
		message(WARNING "_webos_nyx_support_init(): Detected second call. This should only be called ONCE")
		return()
	endif()

	# Cache a default value for NYX_MODULES_REQUIRED
	set(NYX_MODULES_REQUIRED "" CACHE STRING "List of modules required")

	# We have almost certainly been invoked before FindPkgConfig is included by the main CMake script,
	# and we need to use the macros and variables it defines.
	include(FindPkgConfig)
	if (NOT DEFINED PKG_CONFIG_EXECUTABLE)
		message(FATAL_ERROR "_webos_nyx_support_init(): Unable to locate the pkg-config executable")
	endif()


	# Pull in all the variables defined in nyx-lib's pkg-config file
	__nyx_get_pkgconfig_var(NYX_MODULE_DIR nyx_module_dir TRUE)
	__nyx_get_pkgconfig_var(NYX_MODULE_PREFIX nyx_module_prefix FALSE)
	__nyx_get_pkgconfig_var(NYX_MODULE_SUFFIX nyx_module_suffix FALSE)
	__nyx_get_pkgconfig_var(NYX_MODULE_MOCK_DIR nyx_module_mock_dir TRUE)

	# Modify the prefix and suffix for shared libraries to nyx's preferred
	# values (if any are found)

	if(NOT(NYX_MODULE_PREFIX STREQUAL ""))
		set (CMAKE_SHARED_MODULE_PREFIX ${NYX_MODULE_PREFIX})
	endif()

	if(NOT(NYX_MODULE_SUFFIX STREQUAL ""))
		set (CMAKE_SHARED_MODULE_SUFFIX ${NYX_MODULE_SUFFIX})
	endif()

	# Check for NYX and add it to the component's include paths etc.
	pkg_check_modules(NYXLIB REQUIRED nyx)
	include_directories(${NYXLIB_INCLUDE_DIRS})
	webos_add_compiler_flags(ALL ${NYXLIB_CFLAGS_OTHER})

	set(__NYX_MODULE_INITIALIZED TRUE) # Prevent repeated calls.
endmacro()

# Usage: _webos_nyx_parse_modules(<provider acronym> <list of modules provided>
#
# Parses NYX_MODULES_REQUIRED for any mention of the modules provided, and sets
# variables accordingly for use by the parent scoped CMake script.
#
# For example, if invoked as:
#
#	 # NYX_MODULES_REQUIRED == [NYXMOD_OW_DEVICEINFO, NYXMOD_TST_LED, NYXMOD_AOSP_SYSTEM]
#    _webos_nyx_parse_modules(TST SYSTEM LED TOUCHPANEL)
#
# The following variables would be created and set
#
#  NYXMOD_TST_SYSTEM == FALSE
#  NYXMOD_TST_LED == TRUE
#  NYXMOD_TST_TOUCHPANEL == FALSE
#
function(_webos_nyx_parse_modules provider)
	# Ensure NYX_MODULES_REQUIRED is a list as CMake understands it
	string(REGEX REPLACE " +" ";" NMR "${NYX_MODULES_REQUIRED}")

	foreach(module ${ARGN})
		set(module_name "NYXMOD_${provider}_${module}")
		list(FIND NMR "${module_name}" index)

		if(index STREQUAL -1)
			set(result FALSE)
		else()
			set(result TRUE)
		endif()

		set(${module_name} ${result} PARENT_SCOPE)
	endforeach()
endfunction()

# Usage: webos_build_nyx_module(<name> SOURCES <list of source files> LIBRARIES <list of libraries> [MOCK])
#
# <name> defines the library and target
# SOURCES provides a list of source files to be included in building the library
# LIBRARIES lists the libraries requried to link the module (NYX will be added automatically)
# MOCK: if specified, the module is installed in NYXLIB_MODULE_MOCK_DIR instead of NYXLIB_MODULE_DIR
#
function(webos_build_nyx_module module_name)
	cmake_parse_arguments(_wbnm "MOCK" "" "SOURCES;LIBRARIES" ${ARGN})

	if(DEFINED _wbnm_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "webos_build_nyx_module(): Unrecognized arguments: '${_wbnm_UNPARSED_ARGUMENTS}'")
	endif()

	if(NOT _wbnm_SOURCES)
		message(FATAL_ERROR "webos_build_nyx_module(): No Source files listed for module")
	endif()

	add_library(${module_name} MODULE ${_wbnm_SOURCES})
	target_link_libraries(${module_name}  ${NYXLIB_LDFLAGS} ${_wbnm_LIBRARIES})
	_webos_set_bin_permissions(permissions FALSE)

	if(_wbnm_MOCK)
		set(installdir ${NYX_MODULE_MOCK_DIR})
	else()
		set(installdir ${NYX_MODULE_DIR})
	endif()

	install(TARGETS ${module_name} DESTINATION ${installdir} ${permissions})

endfunction()

