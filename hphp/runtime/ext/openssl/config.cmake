HHVM_DEFINE_EXTENSION("openssl"
  SOURCES
    ext_openssl.cpp
  HEADERS
    ext_openssl.h
  SYSTEMLIB
    ext_openssl.php
  DEPENDS
    libOpenSSL
)