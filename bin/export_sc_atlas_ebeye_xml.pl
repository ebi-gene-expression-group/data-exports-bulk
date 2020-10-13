#!/usr/bin/env perl
## export WEB_API_URL="https://wwwdev.ebi.ac.uk/gxa/sc/json"

use strict;
use warnings;

use XML::Writer;
use IO::File;
use DateTime;
use LWP::UserAgent;
use HTTP::Request::Common;
use LWP::Simple;
use XML::Simple qw( :strict );
use File::Basename;
use File::Spec;
use Log::Log4perl;
use JSON::Parse qw( parse_json );
use Encode qw(
    encode
    decode
);

use Atlas::Common qw(
 connect_pg_atlas
 connect_sc_pg_atlas
 create_atlas_site_config
 get_atlas_contrast_details
 get_log_file_header
 get_log_file_name
);

use Data::Dumper;

# Flush buffer after every print.
$| = 1;


# Config for logger.
my $logger_config = q(
 log4perl.rootlogger     = INFO, LOG1, SCREEN
 log4perl.appender.SCREEN   = Log::Log4perl::Appender::Screen
 log4perl.appender.SCREEN.stderr  = 0
 log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
 log4perl.appender.SCREEN.layout.ConversionPattern = %-5p - %m%n
 log4perl.appender.LOG1    = Log::Log4perl::Appender::File
 log4perl.appender.LOG1.filename  = sub { get_log_file_name( "export_atlas_ebeye_xml" ) }
 log4perl.appender.LOG1.header_text = sub { get_log_file_header( "Atlas EB-eye XML dump" ) }
 log4perl.appender.LOG1.mode   = append
 log4perl.appender.LOG1.layout  = Log::Log4perl::Layout::PatternLayout
 log4perl.appender.LOG1.layout.ConversionPattern = %-5p - %m%n
);

# Initialise logger.
Log::Log4perl::init( \$logger_config );
my $logger = Log::Log4perl::get_logger;

# The date in dd-mmm-yyyy format e.g. 14-Nov-2013
my $today = DateTime->today();
my $date = $today->day()."-".$today->month_abbr()."-".$today->year();


sub check_env_var {
  my $var = shift;
  my $suggestion = shift;

  unless(defined $ENV{$var}) {
    $logger->error( "Please define $var env var" );
    $logger->info( "Usually for $var: $suggestion" ) if(defined $suggestion);
    exit 1;
  }
}


check_env_var('ATLAS_PROD');
check_env_var('WEB_API_URL',"should include api url.");

my $atlasProdDir = $ENV{ "ATLAS_PROD" };

# A hash to store some config for things we might want to change later, at the
# top so it's easy to find.
my $configHash = {
 
 # Today's date.
 today => $date,

 # Filename for baselie Atlas experiments info.
 baselineExperimentsFilename => "ebeye_sc_baseline_experiments_export.xml ",

 # Filename for sc baseline Atlas gene data.
 baselineDataFilename => "ebeye_sc_baseline_genes_export.xml ",

 # A description of Atlas. This will go at the top of the XML.
 atlasDescription => "A semantically enriched database of publicly available single cell gene and transcript expression data. The data is re-analysed in-house to detect genes showing interesting baseline expression patterns under the conditions of the original experiment.",

};


my $H_baselineExperimentsInfo = fetch_experiments_info_from_webapi($logger);

# Connect to SC Atlas database.
my $atlasDB = connect_sc_pg_atlas;

# Fetch cell types from db
my $H_baselineCellTypeInfo = $atlasDB->fetch_experiment_celltypes_from_sc_atlasdb( $logger );

# Fetch collections from db
my $H_baselineCollectionInfo = $atlasDB->fetch_experiments_collections_from_sc_atlasdb( $logger);
 
# Get info from webAPI and write XMLs for baseline experiment info.
get_and_write_experiments_info($configHash, $H_baselineExperimentsInfo, $H_baselineCellTypeInfo, $H_baselineCollectionInfo);

my $H_baselineExperimentGeneInfo = $atlasDB->fetch_experiment_genes_from_sc_atlasdb( $logger );

get_and_write_genes_info( $configHash, $H_baselineExperimentGeneInfo );

add_entry_count ( $configHash );

sub get_and_write_genes_info {

    my ($configHash, $H_baselineExperimentGeneInfo) = @_;

 # Files to write XML to Baseline gene data.
 my $baselineDataFilename = $configHash->{ "baselineDataFilename" };
 my $baselineEBeyeXML = IO::File->new(">$baselineDataFilename");
 my $baselineWriter = XML::Writer->new(OUTPUT => $baselineEBeyeXML, DATA_MODE => 1, DATA_INDENT => 4, ENCODING => 'utf-8');

# Today's date
 my $date_string = $configHash->{ "today" };
 
 # A description of Atlas. This will go at the top of the XML.
 my $atlasDescription = $configHash->{ "atlasDescription" };
 
 # Begin XML
 foreach my $writer ($baselineWriter) {
  $writer->xmlDecl("UTF-8");
  $writer->startTag("database");
  $writer->dataElement("name" => "SingleCellExpressionAtlas");
  $writer->dataElement("description" => $atlasDescription);
  $writer->emptyTag("release");
  $writer->dataElement("release_date" => $date_string);
  $writer->dataElement("entry_count" => "ENTRY_COUNT_PLACEHOLDER");
 }
 
 ## write baseline gene info
 add_gene_info( $baselineWriter, $H_baselineExperimentGeneInfo);
 
 # Close entries and database elements for both writers.
 foreach my $writer ($baselineWriter) {
  $writer->endTag("database");
  $writer->end();
 }

 $baselineEBeyeXML->close();

 $logger->info( "SC Baseline Expression Atlas EB-eye gene data exported to $baselineDataFilename" );

}

sub add_gene_info {

 my ($baselineWriter, $H_baselineExperimentGeneInfo) =  @_;
    
## iterate of baseline gene expressed
 foreach my $geneID ( @{$H_baselineExperimentGeneInfo} ){
   
  $baselineWriter->startTag("entry", "id" => $geneID );

  my $H_baselineGeneInfo = fetch_gene_info_from_webapi( $geneID, $logger);
  my $baselineExptCount;
  $baselineExptCount = (scalar @{ $H_baselineGeneInfo->{'results'} });
  $baselineWriter->dataElement("studies_count" => $baselineExptCount);

  if( $baselineExptCount ) {

    foreach my $hash_ref ( @{ $H_baselineGeneInfo->{'results'} } ) {
       
        my $exptAcc = $hash_ref->{'element'}->{'experimentAccession'};
       # print $exptAcc."\n";
       $baselineWriter->startTag("cross_references");

       # Write accessions to XML.
       $baselineWriter->emptyTag("ref", "dbname" => "sc atlas", "dbkey" => $exptAcc);

       my $exp_url = $hash_ref->{'element'}->{'url'};

       $baselineWriter->emptyTag("ref", "dbname" => "sc atlas", "url" => $exp_url);

        # Close cross_references element.
        $baselineWriter->endTag("cross_references");

        # Fill in the additional_fields.
        # Begin element.
        $baselineWriter->startTag("additional_fields");

        foreach my $factor_hash (@{ $hash_ref->{'element'}->{'factors'} }) {
         # print $factor_hash."\n";
          $baselineWriter->dataElement("field" => $factor_hash, "name" => "factors" );
        }

        my $exp_assays = $hash_ref->{'element'}->{'numberOfAssays'};
        #print $exp_assays."\n";

        $baselineWriter->dataElement("field" => $exp_assays, "name" => "numberOfAssays" );

        my $markergenes_hash = @{ $hash_ref->{'element'}->{'markerGenes'} };
            if ($markergenes_hash) {
          #  print "MARKER - $markergenes_hash". "\n";
            $baselineWriter->dataElement("field" => $markergenes_hash, "name" => "markerGenes" );
        }

        # Close the additional_fields element.
        $baselineWriter->endTag("additional_fields");

    }
   }
   $baselineWriter->endTag("entry");
  }
}

sub add_shared_cross_references {
    my ( $writer, $H_baselineGeneInfo ) = @_;

    $writer->startTag("cross_references");

    foreach my $hash_ref ( @{ $H_baselineGeneInfo->{'results'} } ){
       my $exptAcc = $hash_ref->{'element'}->{'experimentAccession'};
       # print $exptAcc."\n";

       # Write accessions to XML.
       $writer->emptyTag("ref", "dbname" => "sc atlas", "dbkey" => $exptAcc);

       my $exp_url = $hash_ref->{'element'}->{'url'};
       
       $writer->emptyTag("ref", "dbname" => "sc atlas", "url" => $exp_url);
    }
   
     # Close cross_references element.
    $writer->endTag("cross_references");

    # Fill in the additional_fields.
    # Begin element.
     $writer->startTag("additional_fields");
}

sub add_shared_additional_fields {
    my ( $writer, $H_baselineGeneInfo ) = @_;

    foreach my $hash_ref ( @{ $H_baselineGeneInfo->{'results'} } ){
   
        foreach my $factor_hash (@{ $hash_ref->{'element'}->{'factors'} }){
          print $factor_hash."\n";
          $writer->dataElement("field" => $factor_hash, "name" => "factors" );
        }   

        my $exp_assays = $hash_ref->{'element'}->{'numberOfAssays'};
        print $exp_assays."\n";

        $writer->dataElement("field" => $exp_assays, "name" => "numberOfAssays" );

        my $markergenes_hash = @{ $hash_ref->{'element'}->{'markerGenes'} };
            if ($markergenes_hash) {
                 print "MARKER - $markergenes_hash". "\n";
            $writer->dataElement("field" => $markergenes_hash, "name" => "markerGenes" );
        }
    }

 # Close the additional_fields element.
 $writer->endTag("additional_fields");
}

## fetch json formatted result for experiments and its titles from WebAPI.
sub fetch_gene_info_from_webapi {

    my ($gene_id,  $logger ) = @_;

    my $url = $ENV{'WEB_API_URL'};

    my $json_hash;

    $url = join("/",$url,"search?ensgene=");
    my $abs_url = $url . $gene_id . "&species=";
    # print $abs_url;
    my $ua = LWP::UserAgent->new;
    my $response;
    $response =  $ua->get($abs_url);
    $logger->info( "Querying for single cell gene $gene_id from web API" );

    if ($response->is_success) {
     $json_hash = parse_json(decode ('UTF-8', $response->content));
    }
    else {
     die $response->status_line;
    }

    return $json_hash;
}

## fetch json formatted result for experiments and its titles from WebAPI.
sub fetch_experiments_info_from_webapi {

    my ( $logger ) = @_;

    my $url = $ENV{'WEB_API_URL'};

    my $json_hash;

    my $abs_url = join("/",$url,"experiments");
    my $ua = LWP::UserAgent->new;
    my $response;
    $response =  $ua->get($abs_url);
    $logger->info( "Querying for single cell experiments from web API" );

    if ($response->is_success) {
     $json_hash = parse_json(decode ('UTF-8', $response->content));
    }
    else {
     die $response->status_line;
    }

    return $json_hash;
}

# get_and_write_experiments_info
#  - Retrieve differential and baseline experiments information from Atlas
#  database and write it to XML dump files (differential to one, baseline to
#  another).
sub get_and_write_experiments_info {

 my ($configHash, $H_baselineExperimentsInfo, $H_baselineCellTypeInfo, $H_baselineCollectionInfo) = @_;

 # Files to write XML to.
 # Baseline data.
 my $baselineExperimentsFilename = $configHash->{ "baselineExperimentsFilename" };
 my $baselineExperimentsEBeyeXML = IO::File->new(">$baselineExperimentsFilename");

 # A description of Atlas. This will go at the top of the XML.
 my $atlasDescription = $configHash->{ "atlasDescription" };

 # New XML writers with newlines and nice indentation.
 # Baseline one.
 my $baselineExperimentsWriter = XML::Writer->new(OUTPUT => $baselineExperimentsEBeyeXML, DATA_MODE => 1, DATA_INDENT => 4);

 # Today's date.
 my $date_string = $configHash->{ "today" };

 # Begin XML
 foreach my $writer ($baselineExperimentsWriter) {
  $writer->xmlDecl("UTF-8");
  $writer->startTag("database");
  $writer->dataElement("name" => "SingleCellExpressionAtlas");
  $writer->dataElement("description" => $atlasDescription);
  $writer->emptyTag("release");
  $writer->dataElement("release_date" => $date_string);
 }

 # Count the number of experiments for each type.
 my $baselineExperimentsCount = ( scalar (@{ $H_baselineExperimentsInfo->{'experiments'}}) );
 $baselineExperimentsWriter->dataElement("entry_count" => $baselineExperimentsCount);

 # Start the "entries" element.
 foreach my $writer ($baselineExperimentsWriter) {
  $writer->startTag("entries");
 }

 # Write the baseline experiments info.
 add_experiments_info($baselineExperimentsWriter, $H_baselineExperimentsInfo, $H_baselineCellTypeInfo, $H_baselineCollectionInfo);

 # Close entries and database elements for both writers.
 foreach my $writer ($baselineExperimentsWriter) {
  $writer->endTag("entries");
  $writer->endTag("database");
  $writer->end();
 }

 # Close files.
 $baselineExperimentsEBeyeXML->close();

 # Log that we're done.
 $logger->info( "Baseline SC Expression Atlas EB-eye experiments info exported to $baselineExperimentsFilename" );
}


# add_experiments_info
#  - Write XML using experiments info from Atlas database.
sub add_experiments_info {
 my ($writer, $H_baselineExperimentsInfo, $H_baselineCellTypeInfo, $H_baselineCollectionInfo) = @_;

 foreach my $hash_ref ( @{ $H_baselineExperimentsInfo->{'experiments'} } ){
   my $exptAcc = $hash_ref->{'experimentAccession'};
  
  # Start the entry for this experiment.
  # Add the accession as the "id".
  $writer->startTag("entry", "id" => $exptAcc);

  # Add the accession as the "name".
  $writer->dataElement("name" => $exptAcc);

  # Add the title as the "description".
  $writer->dataElement("description" => $hash_ref->{ "experimentDescription" });

  $writer->startTag("additional_fields");
  
  $writer->dataElement("field" => $hash_ref->{ "species" }, "name" => "species" );

  $writer->dataElement("field" => @{$hash_ref->{ "technologyType"}}, "name" => "technology");
  
  ## factors included in each experiment
    foreach my $factor (@{ $hash_ref->{ "experimentalFactors" } }){
         $writer->dataElement("field" => $factor, "name" => "factors" );
    }
  ## cell types included in each experiment
    foreach my $celltype (@{ $H_baselineCellTypeInfo->{ $exptAcc } }){
         $writer->dataElement("field" => $celltype, "name" => "celltype" );
    }

  ## collections included in each experiment
    foreach my $collection (@{ $H_baselineCollectionInfo->{ $exptAcc } }){
         $writer->dataElement("field" => $collection, "name" => "collection" );
    }

  $writer->endTag("additional_fields");

  # Add the date as "creation" date, "last_modification" and publication" date.
  $writer->startTag("dates");

  # format datefield to exclude any time stamps and retain only date
  my $dateformat=($hash_ref->{ "lastUpdate" });

  $writer->emptyTag("date", "type" => "creation", "value" => $dateformat);
  $writer->emptyTag("date", "type" => "last_modification", "value" => $dateformat);
  $writer->emptyTag("date", "type" => "publication", "value" => $dateformat);
  $writer->endTag("dates");

  # Start the "cross_references" element and add the accession as
  # ArrayExpress cross-reference.
  $writer->startTag("cross_references");
  $writer->emptyTag("ref", "dbname" => "arrayexpress", "dbkey" => $exptAcc);
  $writer->endTag;

  # End this entry.
  $writer->endTag("entry");
 }
}

sub add_entry_count {

 my ( $configHash ) = @_;

 my $baselineDataFilename = $configHash->{ "baselineDataFilename" };

 foreach my $xmlFile ( $baselineDataFilename ) {

  $logger->info( "Adding entry count for $xmlFile..." );

  my $entryCount = `grep "<entry id=" $xmlFile | wc -l`;
  chomp $entryCount;

  `perl -pi -e 's/ENTRY_COUNT_PLACEHOLDER/$entryCount/;' $xmlFile`;

  $logger->info( "Entry count added." );
 }
}

