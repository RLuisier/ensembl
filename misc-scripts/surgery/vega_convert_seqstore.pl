use strict;
use warnings;

use Getopt::Long;
use Cwd;

use vars qw(@INC);

#effectively add this directory to the PERL5LIB automatically
my $dir = cwd() . '/' . __FILE__;
my @d = split(/\//, $dir);
pop(@d);
$dir = join('/', @d);
unshift @INC, $dir;


my ($file, $user, $password, $verbose, $force, $help, $schema, $limit);

GetOptions ('file=s'      => \$file,
            'schema=s'    => \$schema,
            'user=s'      => \$user,
            'password=s'  => \$password,
            'verbose'     => \$verbose,
            'force'       => \$force,
            'limit=s'     => \$limit,
            'help'        => sub { &show_help(); exit 1;} );

usage("-file option is required")   if(!$file);
usage("-schema option is required") if(!$schema);
usage() if($help);

open(FILE, $file) or die("Could not open input file '$file'");


my @all_species_converters;

while( my $line = <FILE> ) {
  chomp($line);
  next if $line =~ /^#/;
  next if !$line;

  my ( $species, $host, $source_db_name, $target_db_name ) = 
    split( "\t", $line );

  my $converter;

  eval "require SeqStoreConverter::$species";

  if($@) {
    warn("Could not require conversion module SeqStoreConverter::$species\n" .
         "Using SeqStoreConverter::VegaBasicConverter instead:\n$@");

    require SeqStoreConverter::VegaBasicConverter;
    $species = "VegaBasicConverter";
  }

  {
    no strict 'refs';

    $converter = "SeqStoreConverter::$species"->new
      ( $user, $password, $host, $source_db_name, $target_db_name, 
        $schema, $force, $verbose, $limit );
  }

  push @all_species_converters, $converter;
}

for my $converter ( @all_species_converters ) {
  $converter->debug( "\n\n*** converting " . $converter->source . " to " . 
                     $converter->target() . " ***");
  $converter->transfer_meta();
  $converter->create_coord_systems();
  $converter->create_seq_regions();
  $converter->create_assembly();
  $converter->create_attribs();
  $converter->set_top_level();

  $converter->transfer_dna();
  $converter->transfer_genes();
  $converter->transfer_prediction_transcripts();
  $converter->transfer_features();
  $converter->transfer_stable_ids();
  $converter->copy_other_tables();
  $converter->copy_repeat_consensus();
}


print STDERR "*** All finished ***\n";

sub usage {
  my $msg = shift;

  print STDERR "$msg\n\n" if($msg);

  print STDERR <<EOF;
usage:   perl convert_seqstore <options>

options: -file <input_file>     input file with tab delimited 'species',
                                'host', 'source_db', 'target_db' values
                                on each line

         -schema <table_file>   file containing SQL schema definition

         -user <user>           a mysql db user with read/write priveleges

         -password <password>   the mysql user's password

         -verbose               print out debug statements

         -force                 replace any target dbs that already exists

         -limit <num_rows>      limit the number of features transfered to
                                speed up testing

         -help                  display this message

example: perl convert_seqstore.pl -file converter.input \\
              -schema ../../sql/table.sql -user ensadmin -password secret \\
              -force -verbose

EOF
#'

  exit;
}
