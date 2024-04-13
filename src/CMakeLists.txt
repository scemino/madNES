
fips_begin_app(nes-ui windowed)
    fips_files(nes.c nes-ui-impl.cc)
    if (FIPS_IOS)
        fips_files(ios-info.plist)
    endif()
    fips_deps(common ui)
fips_end_app()
target_compile_definitions(nes-ui PRIVATE CHIPS_USE_UI)
