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

include(GNUInstallDirs)

# ─────────────────────────────────────────────────────────────────────────────
# Standalone build against an INSTALLED vanilla upstream SNode.C.
#
# This project no longer requires the SSO/MFA fork of snode.c. It consumes the
# upstream framework via find_package(snodec) and carries its own previously
# fork-only pieces locally:
#   - the SQLite wrapper  (db-sqlite, src/database/sqlite/)
#   - the Nayuki QR lib   (snodec::nayuki-qrcodegen, src/supplement/qrcodegen/)
#
# Build:  cmake -S . -B build -DCMAKE_PREFIX_PATH=<snodec-install-prefix>
# ─────────────────────────────────────────────────────────────────────────────

option(SNODEC_SSO_MFA "Enable SSO/MFA components" ON)

# Upstream SNode.C framework (installed). KEEP find_package(snodec ...
# http-server-express ...) — this is how the standalone IdP pulls in the
# framework. Each component must be requested explicitly to load its imported
# target: http-server-express-legacy-in provides express/legacy/in/WebApp.h (it
# transitively brings net-in-stream-legacy + core + utils); logger is separate.
find_package(snodec COMPONENTS
    http-server-express
    http-server-express-legacy-in
    net-in-stream-legacy
    logger
    REQUIRED
)

find_package(OpenSSL REQUIRED)
find_package(SQLite3 REQUIRED)

# ── Vendored: Project Nayuki QR generator (MIT, src/supplement/qrcodegen/) ────
# Local replacement for the fork's snodec::nayuki-qrcodegen. Keeping the same
# target + alias name means the auth library's link list is unchanged.
add_library(nayuki-qrcodegen STATIC
    src/supplement/qrcodegen/qrcodegen.cpp
)
add_library(snodec::nayuki-qrcodegen ALIAS nayuki-qrcodegen)
target_include_directories(nayuki-qrcodegen PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/supplement/qrcodegen>"
)
target_compile_features(nayuki-qrcodegen PUBLIC cxx_std_17)
set_property(TARGET nayuki-qrcodegen PROPERTY POSITION_INDEPENDENT_CODE ON)

# ── Vendored: SQLite wrapper (db-sqlite, src/database/sqlite/) ────────────────
# Local replacement for the fork's db-sqlite. SQLite3::SQLite3 comes from CMake's
# canonical find_package(SQLite3); no pkg-config aliasing needed.
add_library(db-sqlite STATIC
    src/database/sqlite/SqliteDatabase.cpp
)
# Link via FindSQLite3's result variables rather than the SQLite3::SQLite3
# imported target: find_package(snodec) transitively resolves SQLite3 too, which
# can leave the imported target out of this directory's scope even though the
# variables are set ("-- Found SQLite3 ..."). Variables are always in scope.
target_link_libraries(db-sqlite PUBLIC ${SQLite3_LIBRARIES})
target_include_directories(db-sqlite PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>"
    ${SQLite3_INCLUDE_DIRS}
)
set_property(TARGET db-sqlite PROPERTY POSITION_INDEPENDENT_CODE ON)

# ── Auth library ──────────────────────────────────────────────────────────────
add_library(auth STATIC
    src/auth/JwtVerifier.cpp
    src/auth/JwtSigner.cpp
    src/auth/UserContext.cpp
    src/auth/AuthMiddleware.cpp
    src/auth/Totp.cpp
    src/auth/QrCodeGenerator.cpp
)

target_link_libraries(auth PUBLIC
    snodec::http-server-express
    snodec::nayuki-qrcodegen
    ${OPENSSL_LIBRARIES}
)

target_include_directories(auth PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>"
    "$<BUILD_INTERFACE:${OPENSSL_INCLUDE_DIRS}>"
)

# ── auth_idp executable ───────────────────────────────────────────────────────
add_executable(auth_idp
    src/apps/auth_idp/IdpServer.cpp
)

target_link_libraries(auth_idp PRIVATE
    auth
    db-sqlite
    snodec::http-server-express-legacy-in
    snodec::net-in-stream-legacy
    snodec::logger
)

target_include_directories(auth_idp PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

install(
    TARGETS auth_idp
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    COMPONENT auth_idp
)
