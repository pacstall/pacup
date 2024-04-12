use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'Pacup',
    VERSION_FROM => 'bin/pacup',
    ABSTRACT => 'Pacscript Updater',
    LICENSE => 'gpl_3',
    AUTHOR => 'Vigress <vig@disroot.org>',
    EXE_FILES => ['bin/pacup'],
    INSTALLDIRS => 'vendor',
    dist => { COMPRESS => 'gzip', SUFFIX => 'gz' },
);
