use lib 't';
use TestUtils qw(test_getter_setter);

BEGIN { $| = 1;  
	use Test;
	plan tests => 9;
}

use MultiTestDB;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::RawContig;
use Bio::Seq;


my $multi = MultiTestDB->new;
 
# get a core DBAdaptor
#
my $dba = $multi->get_DBAdaptor("core");
my $sfa = $dba->get_SimpleFeatureAdaptor;

#
# 1 create a new Simplefeature
#
$sf = new Bio::EnsEMBL::SimpleFeature;
ok($sf);


#
# 2-7 test the basic getter and setters
#

# 2 start
my $test = 0;
$test = test_getter_setter($sf,'start',10);
ok($test);

# 3 end
$test = test_getter_setter($sf,'end',14);
ok($test);

# 4 strand
$test = test_getter_setter($sf,'strand',1);
ok($test);

# 5 score
$test = test_getter_setter($sf,'score',42);
ok($test);

# 6 display_label
$test = test_getter_setter($sf,'display_label','dummy_label');
ok($test);

# 7 dbID
$test = test_getter_setter($sf,'dbID',42);
ok($test);


#
# 8 attach a contig
#
# create a dummy seq and contig
#
my $seq  = Bio::Seq->new(-seq => 'ATGCAGCTAGCATCGATGACATCG',
                         -id => 'dummy_contig',
                         -accession => 'dummy_contig');
  
my $contig = Bio::EnsEMBL::RawContig->new();
 
my $name =  'dummy_contig';
$contig->id($name);
$contig->embl_offset(0);
$contig->seq($seq);

# now attach the contig

$sf->contig($contig);
ok($sf);


#
# 9 check adaptor attaching
#
$sf->adaptor($sfa);
ok($sf->adaptor->isa('Bio::EnsEMBL::DBSQL::SimpleFeatureAdaptor'));