use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Weather::Underground',
    'VERSION_FROM' => 'Underground.pm',
    'DISTNAME' => 'Weather-Underground',
    'PREREQ_PM' => { 'LWP::Simple' => 0 },
    'dist' => { COMPRESS => "gzip -9", SUFFIX => "gz" },
);
