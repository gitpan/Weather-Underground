#
# $Header: /cvsroot/weather::underground/Weather/Underground/Makefile.PL,v 1.3 2002/10/31 01:04:52 mina Exp $
#
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'	=> 'Weather::Underground',
    'VERSION_FROM' => 'Underground.pm',
    'DISTNAME' => 'Weather-Underground',
    'PREREQ_PM' => { 'LWP::Simple' => 0 },
    'dist' => { COMPRESS => "gzip -9", SUFFIX => "gz" },
);
