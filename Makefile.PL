#!/usr/bin/perl

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'POE::Class::Net',
    VERSION      => '0.01',
    PMLIBDIRS    => [ qw(lib) ],
    PREREQ_PM    => {
        POE => '0.27',
        'POE::Class' => '0.01'
    },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (AUTHOR     => 'Scott Beck <sbeck@gossamer-threads.com>') : ()),
);


