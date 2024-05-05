use ExtUtils::MakeMaker;
use strict;
use warnings qw(all);

WriteMakefile(
    NAME => 'Pacup',
    ABSTRACT => 'Pacscript Updater',
    VERSION_FROM => 'pacup',
    LICENSE => 'gpl_3',
    AUTHOR => 'Vigress <vig@disroot.org>',
    EXE_FILES => ['pacup'],
    INSTALLDIRS => 'vendor',
    dist => { COMPRESS => 'gzip', SUFFIX => 'gz' },
    PREREQ_PM => {
        "Cwd" => 0,
        "Data::Compare" => 0,
        "Dpkg::Version" => 0,
        "ExtUtils::MakeMaker" => 0,
        "File::Basename" => 0,
        "File::chdir" => 0,
        "File::Copy" => 0,
        "File::Path" => 0,
        "File::Temp" => 0,
        "Getopt::Long" => 0,
        "IPC::System::Simple" => 0,
        "JSON" => 0,
        "List::MoreUtils" => 0,
        "List::Util" => 0,
        "LWP::UserAgent" => 0,
        "Pod::Usage" => 0,
        "Term::ANSIColor" => 0,
        "Term::ProgressBar" => 0,
    }
);
