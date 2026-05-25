# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_audio")
project(${PROJECT_NAME} LANGUAGES CXX)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    # NOTE: On some Windows setups, CMake's internal downloader can fail silently and leave a 0-byte file
    # (e.g. due to TLS/cert/proxy restrictions). Use PowerShell as the primary downloader on Windows.
    if(WIN32)
      execute_process(
        COMMAND powershell -NoProfile -ExecutionPolicy Bypass -Command
          "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Import-Module BitsTransfer -ErrorAction Stop; Start-BitsTransfer -Source '${url}' -Destination '${locationForArchive}' -ErrorAction Stop } catch { try { Invoke-WebRequest -Uri '${url}' -OutFile '${locationForArchive}' -UseBasicParsing -ErrorAction Stop } catch { Write-Error $_; exit 1 } }"
        RESULT_VARIABLE PS_RESULT
        OUTPUT_VARIABLE PS_OUT
        ERROR_VARIABLE PS_ERR
      )
      if(NOT PS_RESULT EQUAL 0)
        message(STATUS "PowerShell download failed (code=${PS_RESULT}). Falling back to CMake downloader.\n${PS_ERR}")
        file(DOWNLOAD "${url}" "${locationForArchive}" SHOW_PROGRESS)
      endif()
    else()
      file(DOWNLOAD "${url}" "${locationForArchive}" SHOW_PROGRESS)
    endif()
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Treat a 0-byte download as a failure.
    if(EXISTS "${locationForArchive}")
      file(SIZE "${locationForArchive}" ARCHIVE_SIZE)
      if(ARCHIVE_SIZE EQUAL 0)
        file(REMOVE "${locationForArchive}")
        message(FATAL_ERROR "${locationForArchive} Download failed (0 bytes). If GitHub releases are blocked on your network, pre-download the archive and set MEDIA_KIT_LIBMPV_ARCHIVE to its full path, then re-build.")
      endif()
    endif()

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# Thanks to Mitchel Stewart (https://github.com/Quackdoc) for providing patches to generate minimal libmpv & FFmpeg audio specific builds.

# libmpv archive containing the pre-built shared libraries & headers.
set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")

# Download URL & MD5 hash of the libmpv archive.
set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/${LIBMPV}")
set(LIBMPV_MD5 "cd738e16e2a19626d7cfa48801524f8c")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

# If GitHub downloads are blocked (common on some networks), you can pre-download the archive and
# point to it via an environment variable:
#   $env:MEDIA_KIT_LIBMPV_ARCHIVE='C:\\path\\to\\mpv-dev-x86_64-20230924-git-652a1dd.7z'
if(DEFINED ENV{MEDIA_KIT_LIBMPV_ARCHIVE} AND EXISTS "$ENV{MEDIA_KIT_LIBMPV_ARCHIVE}")
  message(STATUS "Using pre-downloaded libmpv archive: $ENV{MEDIA_KIT_LIBMPV_ARCHIVE}")
  set(LIBMPV_ARCHIVE "$ENV{MEDIA_KIT_LIBMPV_ARCHIVE}")
else()
  download_and_verify(
    ${LIBMPV_URL}
    ${LIBMPV_MD5}
    ${LIBMPV_ARCHIVE}
  )
endif()

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
    COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
    COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
    COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
    WORKING_DIRECTORY "${LIBMPV_SRC}"
  )
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_audio_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_audio/media_kit_libs_windows_audio_plugin_c_api.h"
  "media_kit_libs_windows_audio_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_audio_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  PARENT_SCOPE
)
