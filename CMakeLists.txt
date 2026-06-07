cmake_minimum_required(VERSION 3.18)

project(
    snodec-auth-idp
    DESCRIPTION "SNode.C Identity Provider — OAuth2 + PKCE + TOTP MFA + JWT RS256"
    VERSION 1.0.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── Compiler flags (match SNode.C upstream settings) ─────────────────────────
add_compile_options(
    -Wall -Wextra -Wconversion -Wuninitialized
    -Wunreachable-code -Wfloat-equal -fexec-charset=UTF-8
    -Wno-shadow -Wno-psabi
)

if(NOT APPLE)
    add_link_options(LINKER:--as-needed)
endif()

# ── Build mode: in-tree (inside snode.c source tree) ─────────────────────────
# This CMakeLists.txt is designed to be placed inside the snode.c source tree
# by the Dockerfile build script. The SNODEC_INTREE_BUILD variable is set by
# the parent CMakeLists.txt in src/ so all SNode.C targets are available.
#
# Directory layout expected:
#   <snode.c_root>/
#     src/
#       apps/
#         auth_idp/       ← this project's app code
#       auth/             ← this project's auth library code
# ─────────────────────────────────────────────────────────────────────────────

option(SNODEC_SSO_MFA "Enable SSO/MFA components" ON)

# ── Auth library ──────────────────────────────────────────────────────────────
find_package(OpenSSL REQUIRED)

add_library(auth STATIC
    src/auth/JwtVerifier.cpp
    src/auth/JwtSigner.cpp
    src/auth/UserContext.cpp
    src/auth/AuthMiddleware.cpp
    src/auth/Totp.cpp
    src/auth/QrCodeGenerator.cpp
)

target_link_libraries(auth PUBLIC
    http-server-express
    snodec::logger
    snodec::utils
    snodec::nayuki-qrcodegen
    ${OPENSSL_LIBRARIES}
)

target_include_directories(auth PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/src>"
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>"
    "$<BUILD_INTERFACE:${OPENSSL_INCLUDE_DIRS}>"
    "$<INSTALL_INTERFACE:include/snode.c>"
)

# ── auth_idp executable ───────────────────────────────────────────────────────
find_package(SQLite3 REQUIRED)

add_executable(auth_idp
    src/apps/auth_idp/IdpServer.cpp
)

target_link_libraries(auth_idp PRIVATE
    auth
    db-sqlite
    http-server-express
    net-in-stream-legacy
    snodec::logger
)

target_include_directories(auth_idp PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

install(
    TARGETS auth_idp
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    COMPONENT apps
)
