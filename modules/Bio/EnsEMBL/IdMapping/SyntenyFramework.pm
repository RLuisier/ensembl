package Bio::EnsEMBL::IdMapping::SyntenyFramework;

=head1 NAME


=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 METHODS


=head1 REALTED MODULES


=head1 LICENCE

This code is distributed under an Apache style licence. Please see
http://www.ensembl.org/info/about/code_licence.html for details.

=head1 AUTHOR

Patrick Meidl <meidl@ebi.ac.uk>, Ensembl core API team

=head1 CONTACT

Please post comments/questions to the Ensembl development list
<ensembl-dev@ebi.ac.uk>

=cut


use strict;
use warnings;
no warnings 'uninitialized';

use Bio::EnsEMBL::IdMapping::Serialisable;
our @ISA = qw(Bio::EnsEMBL::IdMapping::Serialisable);

use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::Utils::ScriptUtils qw(path_append);
use Bio::EnsEMBL::IdMapping::SyntenyRegion;
use Bio::EnsEMBL::IdMapping::ScoredMappingMatrix;

use FindBin qw($Bin);
FindBin->again;

sub new {
  my $caller = shift;
  my $class = ref($caller) || $caller;
  my $self = $class->SUPER::new(@_);

  my ($logger, $conf, $cache) = rearrange(['LOGGER', 'CONF', 'CACHE'], @_);

  unless ($logger and ref($logger) and
          $logger->isa('Bio::EnsEMBL::Utils::Logger')) {
    throw("You must provide a Bio::EnsEMBL::Utils::Logger for logging.");
  }
  
  unless ($conf and ref($conf) and
          $conf->isa('Bio::EnsEMBL::Utils::ConfParser')) {
    throw("You must provide configuration as a Bio::EnsEMBL::Utils::ConfParser object.");
  }
  
  unless ($cache and ref($cache) and
          $cache->isa('Bio::EnsEMBL::IdMapping::Cache')) {
    throw("You must provide configuration as a Bio::EnsEMBL::IdMapping::Cache object.");
  }
  
  # initialise
  $self->logger($logger);
  $self->conf($conf);
  $self->cache($cache);
  $self->{'cache'} = [];

  return $self;
}


sub build_synteny {
  my $self = shift;
  my $mappings = shift;
  
  unless ($mappings and
          $mappings->isa('Bio::EnsEMBL::IdMapping::MappingList')) {
    throw('Need a gene Bio::EnsEMBL::IdMapping::MappingList.');
  }

  # create a synteny region for each mapping
  my @synteny_regions = ();

  foreach my $entry (@{ $mappings->get_all_Entries }) {
    
    my $source_gene = $self->cache->get_by_key('genes_by_id', 'source',
      $entry->source);
    my $target_gene = $self->cache->get_by_key('genes_by_id', 'target',
      $entry->target);

    my $sr = Bio::EnsEMBL::IdMapping::SyntenyRegion->new_fast([
      $source_gene->start,
      $source_gene->end,
      $source_gene->strand,
      $source_gene->seq_region_name,
      $target_gene->start,
      $target_gene->end,
      $target_gene->strand,
      $target_gene->seq_region_name,
      $entry->score,
    ]);

    push @synteny_regions, $sr;
  }

  unless (@synteny_regions) {
    $self->logger->warning("No synteny regions could be identified.\n");
    return;
  }

  # sort synteny regions
  #my @sorted = sort _by_overlap @synteny_regions;
  my @sorted = reverse sort {
    $a->source_seq_region_name cmp $b->source_seq_region_name ||
    $a->source_start <=> $b->source_start ||
    $a->source_end <=> $b->source_end } @synteny_regions;

  $self->logger->info("SyntenyRegions before merging: ".scalar(@sorted)."\n");
  
  # now create merged regions from overlapping syntenies, but only merge a
  # maximum of 2 regions (otherwise you end up with large synteny blocks which
  # won't contain much information in this context)
  my $last_merged = 0;
  my $last_sr = shift(@sorted);

  while (my $sr = shift(@sorted)) {
    #$self->logger->debug("this ".$sr->to_string."\n");
  
    my $merged_sr = $last_sr->merge($sr);

    if (! $merged_sr) {
      unless ($last_merged) {
        $self->add_SyntenyRegion($last_sr->stretch(2));
        #$self->logger->debug("nnn  ".$last_sr->to_string."\n");
      }
      $last_merged = 0;
    } else {
      $self->add_SyntenyRegion($merged_sr->stretch(2));
      #$self->logger->debug("mmm  ".$merged_sr->to_string."\n");
      $last_merged = 1;
    }
    
    $last_sr = $sr;
  }

  # deal with last synteny region in @sorted
  unless ($last_merged) {
    $self->add_SyntenyRegion($last_sr->stretch(2));
    $last_merged = 0;
  }

  #foreach my $sr (@{ $self->get_all_SyntenyRegions }) {
  #  $self->logger->debug("SRs ".$sr->to_string."\n");
  #}
  
  $self->logger->info("SyntenyRegions after merging: ".scalar(@{ $self->get_all_SyntenyRegions })."\n");

}


sub _by_overlap {
  # first sort by seq_region
  my $retval = ($b->source_seq_region_name cmp $a->source_seq_region_name);
  return $retval if ($retval);

  # then sort by overlap:
  # return -1 if $a is downstream, 1 if it's upstream, 0 if they overlap
  if ($a->source_end < $b->source_start) { return 1; }
  if ($a->source_start < $b->source_end) { return -1; }
  return 0;
}


sub add_SyntenyRegion {
  push @{ $_[0]->{'cache'} }, $_[1];
}


sub get_all_SyntenyRegions {
  return $_[0]->{'cache'};
}


sub rescore_gene_matrix_lsf {
  my $self = shift;
  my $matrix = shift;

  unless ($matrix and
          $matrix->isa('Bio::EnsEMBL::IdMapping::ScoredMappingMatrix')) {
    throw('Need a Bio::EnsEMBL::IdMapping::ScoredMappingMatrix.');
  }

  # serialise SyntenyFramework to disk
  $self->logger->debug("Serialising SyntenyFramework...\n", 0, 'stamped');
  $self->write_to_file;
  $self->logger->debug("Done.\n", 0, 'stamped');

  # split the ScoredMappingMatrix into chunks and write to disk
  my $matrix_size = $matrix->size;
  $self->logger->debug("Scores before rescoring: $matrix_size.\n");

  my $num_jobs = $self->conf->param('synteny_rescore_jobs') || 20;
  $num_jobs++;

  my $dump_path = path_append($self->conf->param('dumppath'),
    'matrix/synteny_rescore');

  $self->logger->debug("Creating sub-matrices...\n", 0, 'stamped');
  foreach my $i (1..$num_jobs) {
    my $start = (int($matrix_size/($num_jobs-1)) * ($i - 1)) + 1;
    my $end = int($matrix_size/($num_jobs-1)) * $i;
    $self->logger->debug("$start-$end\n", 1);
    my $sub_matrix = $matrix->sub_matrix($start, $end);
    
    $sub_matrix->cache_file_name("gene_matrix_synteny$i.ser");
    $sub_matrix->dump_path($dump_path);
    
    $sub_matrix->write_to_file;
  }
  $self->logger->debug("Done.\n", 0, 'stamped');

  # create an empty lsf log directory
  my $logpath = path_append($self->logger->logpath, 'lsf_synteny_rescore');
  system("rm -rf $logpath") == 0 or
    $self->logger->error("Unable to delete lsf log dir $logpath: $!\n");
  system("mkdir -p $logpath") == 0 or
    $self->logger->error("Can't create lsf log dir $logpath: $!\n");

  # build lsf command
  my $lsf_name = 'idmapping_synteny_rescore_'.time;

  my $options = $self->conf->create_commandline_options(
      logauto       => 1,
      logautobase   => "synteny_rescore_",
      logpath       => $logpath,
      interactive   => 0,
      is_component  => 1,
  );

  my $cmd = qq{$Bin/synteny_rescore.pl $options --index \$LSB_JOBINDEX};

  my $pipe = qq{|bsub -J$lsf_name\[1-$num_jobs\] } .
    qq{-o $logpath/synteny_rescore.\%I.out } .
    qq{-e $logpath/synteny_rescore.\%I.err } .
    $self->conf->param('lsf_opt_synteny_rescore');

  # run lsf job array
  $self->logger->info("Submitting $num_jobs jobs to lsf.\n");
  $self->logger->debug("$cmd\n\n");

  local *BSUB;
  open BSUB, $pipe or
    $self->logger->error("Could not open open pipe to bsub: $!\n");

  print BSUB $cmd;
  $self->logger->error("Error submitting synteny rescoring jobs: $!\n")
    unless ($? == 0); 
  close BSUB;

  # submit dependent job to monitor finishing of jobs
  $self->logger->info("Waiting for jobs to finish...\n", 0, 'stamped');

  my $dependent_job = qq{bsub -K -w "ended($lsf_name)" -q small } .
    qq{-o $logpath/synteny_rescore_depend.out /bin/true};

  system($dependent_job) == 0 or
    $self->logger->error("Error submitting dependent job: $!\n");

  $self->logger->info("All jobs finished.\n", 0, 'stamped');

  # check for lsf errors
  sleep(5);
  my $err;
  foreach my $i (1..$num_jobs) {
    $err++ unless (-e "$logpath/synteny_rescore_$i.success");
  }

  if ($err) {
    $self->logger->error("At least one of your jobs failed.\nPlease check the logfiles at $logpath for errors.\n");
  }

  # merge and return matrix
  $self->logger->debug("Merging rescored matrices...\n");
  $matrix->flush;

  foreach my $i (1..$num_jobs) {
    # read partial matrix created by lsf job from file
    my $sub_matrix = Bio::EnsEMBL::IdMapping::ScoredMappingMatrix->new(
      -DUMP_PATH   => $dump_path,
      -CACHE_FILE  => "gene_matrix_synteny$i.ser",
    );
    $sub_matrix->read_from_file;

    # merge with main matrix
    $matrix->merge($sub_matrix);
  }

  $self->logger->debug("Done.\n");
  $self->logger->debug("Scores after rescoring: ".$matrix->size.".\n");
  
  return $matrix;
}


# 
# retain 70% of old score and build other 30% from synteny match
#
sub rescore_gene_matrix {
  my $self = shift;
  my $matrix = shift;

  unless ($matrix and
          $matrix->isa('Bio::EnsEMBL::IdMapping::ScoredMappingMatrix')) {
    throw('Need a Bio::EnsEMBL::IdMapping::ScoredMappingMatrix.');
  }

  my $retain_factor = 0.7;

  foreach my $entry (@{ $matrix->get_all_Entries }) {
    my $source_gene = $self->cache->get_by_key('genes_by_id', 'source',
      $entry->source);

    my $target_gene = $self->cache->get_by_key('genes_by_id', 'target',
      $entry->target);

    my $highest_score = 0;

    foreach my $sr (@{ $self->get_all_SyntenyRegions }) {
      my $score = $sr->score_location_relationship($source_gene, $target_gene);
      $highest_score = $score if ($score > $highest_score);
    }

    #$self->logger->debug("highscore ".$entry->to_string." ".
    #  sprintf("%.6f\n", $highest_score));

    $matrix->set_score($entry->source, $entry->target,
      ($entry->score * 0.7 + $highest_score * 0.3));
  }

  return $matrix;
}


=head2 logger

  Arg[1]      : (optional) Bio::EnsEMBL::Utils::Logger - the logger to set
  Example     : $object->logger->info("Starting ID mapping.\n");
  Description : Getter/setter for logger object
  Return type : Bio::EnsEMBL::Utils::Logger
  Exceptions  : none
  Caller      : constructor
  Status      : At Risk
              : under development

=cut

sub logger {
  my $self = shift;
  $self->{'_logger'} = shift if (@_);
  return $self->{'_logger'};
}


=head2 conf

  Arg[1]      : (optional) Bio::EnsEMBL::Utils::ConfParser - the configuration
                to set
  Example     : my $dumppath = $object->conf->param('dumppath');
  Description : Getter/setter for configuration object
  Return type : Bio::EnsEMBL::Utils::ConfParser
  Exceptions  : none
  Caller      : constructor
  Status      : At Risk
              : under development

=cut

sub conf {
  my $self = shift;
  $self->{'_conf'} = shift if (@_);
  return $self->{'_conf'};
}


=head2 cache

  Arg[1]      : (optional) Bio::EnsEMBL::IdMapping::Cache - the cache to set
  Example     : $object->cache->read_from_file('source');
  Description : Getter/setter for cache object
  Return type : Bio::EnsEMBL::IdMapping::Cache
  Exceptions  : none
  Caller      : constructor
  Status      : At Risk
              : under development

=cut

sub cache {
  my $self = shift;
  $self->{'_cache'} = shift if (@_);
  return $self->{'_cache'};
}


1;

