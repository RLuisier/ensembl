#!/farm/babs/redhat6/bin/perl

use lib "$ENV{HOME}/src/bioperl-1.2.3";
use lib "$ENV{HOME}/src/ensembl/modules";
use lib "$ENV{HOME}/src/ensembl-compara/modules";
use lib "$ENV{HOME}/src/ensembl-variation/modules";
use lib "$ENV{HOME}/src/ensembl-funcgen/modules";

#In bash:
#PERL5LIB=${PERL5LIB}:${HOME}/src/bioperl-1.2.3
#PERL5LIB=${PERL5LIB}:${HOME}/src/ensembl/modules
#PERL5LIB=${PERL5LIB}:${HOME}/src/ensembl-compara/modules
#PERL5LIB=${PERL5LIB}:${HOME}/src/ensembl-variation/modules
#PERL5LIB=${PERL5LIB}:${HOME}/src/ensembl-funcgen/modules
#export PERL5LIB