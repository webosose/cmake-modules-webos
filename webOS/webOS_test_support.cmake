# - Common CMake code for all Open webOS components which build nyx modules
#
# Any Open webOS component whose root CMakeLists.txt is written by us, and
# which creates test executabless should include this module by observing the
# usage below (they don't need to, but it makes life easier).
#
# Usage:
#
#  include(webOS/webOS)
#  webos_modules_init(...)
#  webos_test_provider()
#
# Their OE recipe must also contain the following line:
#
#  inherit webos_test_provider
#
# This module is never directly included by a component's CMake script. It is
# brought into scope via the nyx_test_provider() macro in the main webOS.cmake
# module. This way, methods like webos_add_test() are only available in
# CMake scripts that have deliberately invoked webos_test_provider().
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

# Usage: _webos_test_support_init([GLIB_TEST] [GOOGLE_TEST])
#
# GLIB_TEST: If specified, indicates that this component uses the glib-2.0 test framework
# GOOGLE_TEST: If specified, indicates that this component uses the g_test framework
#
# Specifying the framework allows this method to check for and add any specific dependencies
# it may require (for example, by invoking webos_use_gtest)
#
# On exit, the following variables have been defined
#
#   WEBOS_CONFIG_BUILD_TESTS      True if tests are to be built
#   WEBOS_CONFIG_INSTALL_TESTS    True if tests are to be installed
#   WEBOS_USES_GOOGLE_TEST        True if this component uses Google's gtest framework
#   WEBOS_USES_GLIB_TEST          True if this component uses glib's g_test framework
#	WEBOS_GTEST_LIBRARIES         If WEBOS_USES_GOOGLE_TEST this contains the path to the gtest
#                                 libraries for linking, else it is empty
#
# NOTE: This macro should be invoked from the root CMake script so that the effects of the
#       enable_testing() macro apply at all levels.
#
# NOTE: This macro is intended to be called from within webOS/webOS.cmake when the component
#       invokes webos_test_provider(). A number of components have appropriated the name
#       webos_add_test for a 'local' method, with a different signature, and injecting it
#       into every namespace causes build failures. This way, a CMake script must deliberately
#       choose to enable this module, and the author must deal with any resulting conflicts.
#
macro(_webos_test_support_init)
	cmake_parse_arguments(_wtsi "GLIB_TEST;GOOGLE_TEST" "" "" ${ARGN})

	if(DEFINED _wtsi_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "_webos_test_support_init(): Unrecognized arguments: '${_wtsi_UNPARSED_ARGUMENTS}'")
	endif()

	set(WEBOS_CONFIG_INSTALL_TESTS FALSE CACHE BOOL "Set to true to install test scripts")

	if (WEBOS_CONFIG_INSTALL_TESTS)
		# Force WEBOS_CONFIG_BUILD_TESTS to True if test installation is requested
		set(WEBOS_CONFIG_BUILD_TESTS TRUE CACHE BOOL "Set to true to build tests" FORCE)
	else()
		# Otherwise, honor any setting from the command line, but default to False if not specified
		set(WEBOS_CONFIG_BUILD_TESTS FALSE CACHE BOOL "Set to true to build tests" )
	endif()

	# Cache the frameworks that are in use
	set(WEBOS_USES_GLIB_TEST ${_wtsi_GLIB_TEST} CACHE BOOL "Indicates if the glib test framework is in use")
	set(WEBOS_USES_GOOGLE_TEST ${_wtsi_GOOGLE_TEST} CACHE BOOL "Indicates if the Google test framework is in use")

	# If we are building tests, bring the test frameworks, and CMakes own test support, into effect
	if (WEBOS_CONFIG_BUILD_TESTS)
		if(WEBOS_USES_GOOGLE_TEST)
			webos_use_gtest()
		endif()

		include(CTest)
		enable_testing()

	endif()

	# Clean up the variables created by cmake_parse_arguments() so they don't linger in the caller's scope
	unset(_wtsi_GLIB_TEST)
	unset(_wtsi_GOOGLE_TEST)
endmacro()

# Usage: webos_add_test(<test name> SOURCES <list of source files> [LIBRARIES <libraries required>)
#
#   <test_name>: Name of the test executable to be created
#   SOURCES provides a list of source files to be included in building the executable
#   LIBRARIES lists the libraries requried to link the test executable
#
# This function can safely be called whether or not WEBOS_CONFIG_{BUILD,INSTALL}_TESTS is true. If
# netiher variable is TRUE, this function is a no-op. This cleans up calling CMake scripts as they
# can simply add tests unconditionally.
#

function(webos_add_test test_name)
	cmake_parse_arguments(_wat "" "" "SOURCES;LIBRARIES" ${ARGN})

	if(DEFINED _wat_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "webos_add_test(): Unrecognized arguments: '${_wat_UNPARSED_ARGUMENTS}'")
	endif()

	if(NOT _wat_SOURCES)
		message(FATAL_ERROR "webos_add_test(): No Source files listed")
	endif()

	if (WEBOS_CONFIG_BUILD_TESTS)
		add_executable(${test_name} ${_wat_SOURCES})
		target_link_libraries(${test_name} ${_wat_LIBRARIES})
		add_test(${test_name} ${test_name})
		if(WEBOS_CONFIG_INSTALL_TESTS)
			install(TARGETS ${test_name} DESTINATION ${WEBOS_INSTALL_TESTSDIR}/${CMAKE_PROJECT_NAME})
		endif()
	endif()

endfunction()
