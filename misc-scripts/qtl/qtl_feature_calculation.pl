# this script tales filled qtl table and tries to calculate 
# qtl_features. It uses marker_feature table.

use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Map::DBSQL::QtlAdaptor;

use Getopt::Long;


my ( $host, $user, $pass, $port, $dbname, $verbose);

$verbose = 0;

GetOptions( "host=s", \$host,
	    "user=s", \$user,
	    "pass=s", \$pass,
	    "port=i", \$port,
	    "dbname=s", \$dbname,
	    "verbose", \$verbose
	  );


if( !$host ) {
  usage();
}


my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new
  (
   -host => $host,
   -user => $user,
   -pass => $pass,
   -dbname => $dbname,
   -port => $port 
  );




my $qtlAdaptor = $db->get_QtlAdaptor();
my $qtls = $qtlAdaptor->fetch_all;

QTL:
for my $qtl ( @$qtls ) {
  my $marker;
  my $features;
  my @positions;

  my %synonyms = %{$qtl->get_synonyms()};
  my ($key) = keys %synonyms;
  my $id = "$key:$synonyms{$key}";

  $marker = $qtl->flank_marker_1;
  if( $marker ) {
    $features = $marker->get_all_MarkerFeatures();
    if( scalar( @$features ) <= 1 ) {
      push( @positions, @$features );
    } else {
      debug( "Non unique flanking marker ".
	     $marker->display_MarkerSynonym->name()." for qtl $id");

      # position of marker not unique, dont place qtl
      next;
    }
  }

  $marker = $qtl->flank_marker_2;
  if( $marker ) {
    $features = $marker->get_all_MarkerFeatures();
    if( scalar( @$features ) <= 1 ) {
      push( @positions, @$features );
    } else {
      # position of marker not unique, dont place qtl
      debug( "Non unique flanking marker ".
             $marker->display_MarkerSynonym->name()." for qtl $id");

      next;
    }
  }

  $marker = $qtl->peak_marker;
  if( $marker ) {
    $features = $marker->get_all_MarkerFeatures();
    if( scalar( @$features ) <= 1 ) {
      push( @positions, @$features );
    } else {
      # position of marker not unique, dont place qtl
      debug( "Non unique peak marker " . 
	     $marker->display_MarkerSynonym->name()." for qtl $id");
      next;
    }
  }

  if( scalar( @positions )) {
    my ( $chr_name, $chr_start, $chr_end, $chromo );
    
    for my $feature ( @positions ) {
      my $empty_slice = Bio::EnsEMBL::Slice->new
	( 
	 -empty => 1,
	 -adaptor => $db->get_SliceAdaptor(),
	 -assembly_type => $db->assembly_type()
	);
      $feature->transform( $empty_slice );

      if( $chr_name && $feature->contig->chr_name() ne $chr_name ) {
	# inconsistent chromsome skip this one
	debug( "Qtl $id was placed on more than one chromosome.." );
	next QTL;
      } 
      $chr_name = $feature->contig->chr_name();
      $chromo = $feature->contig->get_Chromosome();

      if( ! defined $chr_start ) {
	$chr_start = $feature->start();
      } elsif( $feature->start() < $chr_start ) {
	$chr_start = $feature->start();
      }
      if( ! defined $chr_end ) {
	$chr_end = $feature->end();
      } elsif( $feature->end() > $chr_end ) {
	$chr_end = $feature->end();
      }
    }
    
    if( scalar( @positions ) == 1 ) {
      debug( "Qtl $id has only one marker placed." );
    }

    if( $chr_end - $chr_start < 1_000_001 ) {
      my $middle = int(($chr_end + $chr_start)/2);
      debug("Qtl $id smaller then 1MB, expanding around $middle");

      if($middle < 500_001) {
	$middle = 500_001;
	debug("middle is less then 500k, shifting right"); 
      }

      if($middle + 500_000 > $chromo->length) {
       $middle = $chromo->length - 500_000;
       debug("middle is near end of chromosome, shifting left");
     }
      
      $chr_end   = $middle + 500_000;
      $chr_start = $middle - 500_000;

      #
      # for faked chromosomes we could end up with chromosomes less than 1MB
      # doubt this will ever happen in a species w/ qtls but better safe
      # then sorry
      #
      if($chr_end > $chromo->length) {
	$chr_end = $chromo->length();
	debug("qtl is on small fake chromosome, and will span entire length");
      }
      if($chr_start < 1) {
	$chr_start = 1;
	debug("qtl is on small fake chromosome, and will span entire length");
      }
    } elsif( $chr_end - $chr_start > 100_000_000 ) {
      my $span = int(($chr_end - $chr_start + 1) / 1_000_000);
      debug( "Qtl $id covers more than 100MB ($span MB)" );
      next;
    }
    print join( "\t", ($chromo->dbID, $chr_start, $chr_end, $qtl->dbID(), 50 )),"\n";
  }
}

sub debug {
  my $string = shift;
  print STDERR ($string,"\n") if $verbose;
}


sub usage {
  print STDERR <<EOF

  Usage: perl qtl_feature_calculation
          -host hostname
          -user username
          -pass password
          -port portnumber of EnsEMBL SQL server
          -dbname name of EnsEMBL database
          -verbose optional more output

EOF
;
  exit();
}
