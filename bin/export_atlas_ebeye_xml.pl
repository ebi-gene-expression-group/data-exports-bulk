#!/usr/bin/env perl
#
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
  create_atlas_site_config
  get_atlas_contrast_details
  get_log_file_header
  get_log_file_name
);

# Flush buffer after every print.
$| = 1;

# Config for logger.
my $logger_config = q(
  log4perl.rootlogger                               = INFO, LOG1, SCREEN
  log4perl.appender.SCREEN                          = Log::Log4perl::Appender::Screen
  log4perl.appender.SCREEN.stderr                   = 0
  log4perl.appender.SCREEN.layout                   = Log::Log4perl::Layout::PatternLayout
  log4perl.appender.SCREEN.layout.ConversionPattern = %-5p - %m%n
  log4perl.appender.LOG1                            = Log::Log4perl::Appender::File
  log4perl.appender.LOG1.filename                   = sub { get_log_file_name( "export_atlas_ebeye_xml" ) }
  log4perl.appender.LOG1.header_text                = sub { get_log_file_header( "Atlas EB-eye XML dump" ) }
  log4perl.appender.LOG1.mode                       = append
  log4perl.appender.LOG1.layout                     = Log::Log4perl::Layout::PatternLayout
  log4perl.appender.LOG1.layout.ConversionPattern   = %-5p - %m%n
);

# Initialise logger.
Log::Log4perl::init( \$logger_config );
my $logger = Log::Log4perl::get_logger;


#####################
# SETUP: some config.
# -------------------

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
check_env_var('BIOENTITY_PROPERTIES_ENSEMBL',"\$ATLAS_PROD/bioentity_properties/annotations/ensembl");
check_env_var('BIOENTITY_PROPERTIES_WBPS',"\$ATLAS_PROD/bioentity_properties/annotations/wbps");
check_env_var('SOLR_HOST',"should include both host and port if needed.");
check_env_var('WEB_API_URL',"should include api url.");

my $atlasProdDir = $ENV{ "ATLAS_PROD" };
my $bioentity_properties_annotations_ensembl=$ENV{'BIOENTITY_PROPERTIES_ENSEMBL'};
my $bioentity_properties_annotations_wbps=$ENV{'BIOENTITY_PROPERTIES_WBPS'};

# A hash to store some config for things we might want to change later, at the
# top so it's easy to find.
my $configHash = {

  # Today's date.
  today => $date,

  # NCBI taxonomy query URI
  ncbiTaxUri => "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term=",

  # URL for assay group details file.
  assayGroupDetailsURL => "http://wwwdev.ebi.ac.uk/gxa/api/assaygroupsdetails.tsv",

  # Directory where <species>.ensgene.tsv files are.
  bioentityPropertiesEnsemblDir => $bioentity_properties_annotations_ensembl,

  # Directory where <species>.wbpsgene.tsv files are.
  bioentityPropertiesWBPSDir => $bioentity_properties_annotations_wbps,

  # Filename for differential Atlas data.
  differentialDataFilename => "ebeye_differential_genes_export.xml",

  # Filename for differential Atlas experiments info.
  differentialExperimentsFilename => "ebeye_differential_experiments_export.xml",

  # Filename for baseline Atlas data.
  baselineDataFilename => "ebeye_baseline_genes_export.xml ",

  # Filename for baselie Atlas experiments info.
  baselineExperimentsFilename => "ebeye_baseline_experiments_export.xml ",

  # Array for names that go in <cross_references> element.
  crossReferences => [
    "embl",
    "ensfamily",
    "ensprotein",
    "enstranscript",
    "entrezgene",
    "go",
    "uniprot",
    "interpro",
    "unigene",
    "refseq",
  ],

  # Array for names that go in <additional_fields> element.
  additionalFields => [
    "disease",
    "ensfamily_description",
    "gene_biotype",
    "interproterm",
    "mirbase_accession",
    "mirbase_id",
    "goterm",
    "synonym",
    "ortholog",
    "hgnc_symbol",
  ],

  # A description of Atlas. This will go at the top of the XML.
  atlasDescription => "A semantically enriched database of publicly available gene and transcript expression data. The data is re-analysed in-house to detect genes showing interesting baseline and differential expression patterns under the conditions of the original experiment.",

};


############################################
# Get some data from Atlas database.
# ------------------------------------------
# For each gene, we get information about which contrasts in which experiments
# that gene was found to be differentially expressed in, and which assay groups
# in which experiments the gene has baseline expression in.
# Build hashes like:
#   $H_geneIDs2expts2contrasts->{ <gene ID> }->{ <experiment accession> } = [ contrast1, contrast2, ... ]
#   $H_geneIDs2expts2assayGroups->{ <gene ID> }->{ <experiment accession> } = [ assayGroup1, assayGroup2, ... ]

# URL for baseline analytics from solr
my $baselineSolrURL = "http://".$ENV{'SOLR_HOST'}."/solr/bulk-analytics-v1/export?omitHeader=true&fq=expression_level:[0.5+TO+*]&q=*:*&sort=bioentity_identifier+asc&fl=bioentity_identifier,experiment_accession,assay_group_id";
# URL for differential analytics from solr
my $differentialSolrURL = "http://".$ENV{'SOLR_HOST'}."/solr/bulk-analytics-v1/export?omitHeader=true&fq=fold_change:([* TO +1.0] OR [1.0 TO *])+AND+p_value:[0 TO 0.05]&q=*:*&sort=bioentity_identifier+asc&fl=bioentity_identifier,experiment_accession,contrast_id";

my ($H_geneIDs2expts2contrasts, $H_geneIDs2expts2assayGroups) = get_data_from_solr_db($baselineSolrURL, $differentialSolrURL);

# Get baseline and differential expression data from Atlas database and TSV
# files, and write XML dump files.
get_and_write_expression_data_xml($configHash);

# Get info from DB and write XMLs for baseline and differential experiment info.
get_and_write_experiments_info($configHash);

# In baseline and differential genes files, replace entry count placeholder
# with actual entry counts.
add_entry_count( $configHash );

# Some global variables to ensure errors aren't re-printed a gazillion times
my $contrastDetailsMissing = {};
my $atlasIDMissing = {};
my $exptPrivacies = {};

# end
#####

#############
# SUBROUTINES

# get_data_from_solr_db
#   - Connect to Solr database, run query to get experiment accessions and
#   contrast or assay group IDs for each gene. Return hashes like:
#    $H_geneIDs2expts2contrasts->{ <IDENTIFIER> }->{ <EXPERIMENT> } = [ contrast1, contrast2, ... ]
#    $H_geneIDs2expts2assayGroups->{ <IDENTIFIER> }->{ <EXPERIMENT> } = [ assaygroup1, assaygroup2, ... ]

sub get_data_from_solr_db {
  # Ref to hash with config.

  ## query solr database to retrieve baseline and differential genes analytics
  my ( $baseline_solr_url, $differential_solr_url ) = @_;
  # Run the queries to create two hashes, one for differential results and one for
  # baseline results.
  # $H_geneIDs2expts2contrasts->{ <IDENTIFIER> }->{ <EXPERIMENT> } = [ contrast1, contrast2, ... ]
  # $H_geneIDs2expts2assayGroups->{ <IDENTIFIER> }->{ <EXPERIMENT> } = [ assayGroup1, assayGroup2, ... ]
  my $H_geneIDs2expts2assayGroups = fetch_baseline_genes_experiments_assaygroups_from_solrdb( $baseline_solr_url, $logger );
  my $H_geneIDs2expts2contrasts = fetch_degenes_experiments_contrasts_from_solrdb( $differential_solr_url, $logger );
  # Disconnect from the Atlas database.
  #$atlasDB->get_dbh->disconnect;

  # Return the hashes of results.
  return ($H_geneIDs2expts2contrasts, $H_geneIDs2expts2assayGroups);
}


## parse json formatted result for genes associated to experiments accessions and assay group ids.
sub parse_json_from_solr {

  my ( $url, $logger ) =  @_;
  my $ua = LWP::UserAgent->new;

  my $response;
  $response =  $ua->request(GET "$url");

  $logger->info( "response successful." );

  my $json_hash = parse_json(decode ('UTF-8', $response->content));

  $logger->info( "parsing json successful." );

  my $array_ref = $json_hash->{'response'}->{'docs'};

  return $array_ref;
}

# fetch baseline genes, expreriment and assay groups details from solr
sub fetch_baseline_genes_experiments_assaygroups_from_solrdb {

  my ( $url, $logger ) =  @_;

  my $array_ref = parse_json_from_solr ( $url, $logger ) ;

  my ($geneID, $expAcc, $assayGroupID);
  my $geneIDs2expAccs2assayGroupIDs = {};

  foreach my $hash_ref ( @{ $array_ref } ) {
    $geneID = $hash_ref->{'bioentity_identifier'};
    $expAcc = $hash_ref->{'experiment_accession'};
    $assayGroupID = $hash_ref->{'assay_group_id'};

    unless( exists( $geneIDs2expAccs2assayGroupIDs->{ $geneID }->{ $expAcc } ) ) {
      $geneIDs2expAccs2assayGroupIDs->{ $geneID }->{ $expAcc } = [ $assayGroupID ];
    }
    else {
      push @{ $geneIDs2expAccs2assayGroupIDs->{ $geneID }->{ $expAcc } }, $assayGroupID;
    }
  }

  $logger->info( "Baseline query from solr successful." );

  return $geneIDs2expAccs2assayGroupIDs;
}

# fetch differential genes, expreriment and contrast details from solr
sub fetch_degenes_experiments_contrasts_from_solrdb {

  my ( $url, $logger ) =  @_;

  my $array_ref = parse_json_from_solr ( $url, $logger );

  my ($geneID, $expAcc, $contrastID);
  my $geneIDs2expAccs2contrastIDs = {};

  foreach my $hash_ref ( @{ $array_ref } ) {
    $geneID = $hash_ref->{'bioentity_identifier'};
    $expAcc = $hash_ref->{'experiment_accession'};
    $contrastID = $hash_ref->{'contrast_id'};

    unless( exists( $geneIDs2expAccs2contrastIDs->{ $geneID }->{ $expAcc } ) ) {
      $geneIDs2expAccs2contrastIDs->{ $geneID }->{ $expAcc } = [ $contrastID ];
    }
    else {
      push @{ $geneIDs2expAccs2contrastIDs->{ $geneID }->{ $expAcc } }, $contrastID;
    }
  }
  $logger->info( "Differential query from solr successful." );

  return $geneIDs2expAccs2contrastIDs;
}

## fetch json formatted result for experiments and its titles from WebAPI.
sub fetch_experiment_title_from_webapi {

  my ( $expAcc, $logger ) = @_;

  my $url = $ENV{'WEB_API_URL'};

  my $json_hash;
  my $expTitle;

  my $abs_url = join("/",$url,$expAcc);
  my $ua = LWP::UserAgent->new;
  my $response;
  $response =  $ua->get($abs_url);
  $logger->info( "Querying for experiment titles for $expAcc" );

  if ($response->is_success) {
    $json_hash = parse_json(decode ('UTF-8', $response->content));
  }
  else {
    die $response->status_line;
  }

  $expTitle = $json_hash->{'experiment'}->{'description'};

  return $expTitle;
}

# get_and_write_expression_data_xml
#   - Get baseline and differential expression data from Atlas database and TSV
#   files, and write XML dump files.
sub get_and_write_expression_data_xml {
  my ($configHash) = @_;

  # Download and parse contrastdetails.tsv and assaygroupdetails.tsv.
  # - contrastdetails.tsv contains (among other things) accessions, contrast IDs, and test
  # factors and their values for each contrast in Atlas.
  # - assaygroupdetails.tsv contains accessions, assay group IDs, and factors and
  # their values for each assay group in Baseline Atlas.
  #
  # Build hashes like:
  #   $H_expts2contrasts2tests->{ <experiment accession> }->{ <contrast ID> }->{ <test factor type> } = <test factor value>
  #   $H_expts2assayGroups2factors->{ <experiment accession> }->{ <assay group ID> }->{ <factor type> } = <factor value>
  my ($H_expts2contrasts2tests, $H_expts2assayGroups2factors) = get_contrast_assaygroup_details($configHash->{ "contrastDetailsURL" }, $configHash->{ "assayGroupDetailsURL" });

  #########################################################
  # Read *.ensgene.tsv and *.wbpsgene.tsv files and write XML.
  # Now we read each species' *.ensgene.tsv and *.wbpsgene.tsv file and write
  # out the XML dump using info from the TSV file and the Atlas database.

  # Directory where <species>.ensgene.tsv files are.
  my $bioentity_properties_ensembl_dir = $configHash->{ "bioentityPropertiesEnsemblDir" };
  # Directory where <species>.wbpsgene.tsv files are.
  my $bioentity_properties_wbps_dir = $configHash->{ "bioentityPropertiesWBPSDir" };

  # Array of filenames. This includes some that we don't want.
  my @A_tsvFiles = glob("$bioentity_properties_ensembl_dir/*.ensgene.tsv");
  # Array of WBPS files.
  my @wbpsFiles = glob("$bioentity_properties_wbps_dir/*.wbpsgene.tsv");

  # Make a new hash with only the right files -- <species>.ensgene.tsv and <species>.wbpsgene.tsv .
  my $speciesToGeneTSVfiles = {};

  # Go through ensgene files...
  foreach my $file (@A_tsvFiles) {

    if( basename( $file ) =~ /^([a-z]+_[a-z]+)\.ensgene\.tsv$/) {
      my $species = $1;
      $speciesToGeneTSVfiles->{ $species } = $file;
    }
  }

  # Go through wbpsgene files...
  foreach my $file (@wbpsFiles) {
    if( basename( $file ) =~ /^([a-z]+_[a-z]+)\.wbpsgene\.tsv$/) {
      my $species = $1;
      $speciesToGeneTSVfiles->{ $species } = $file;
    }
  }

  # Array for names that go in <cross_references> element.
  my @cross_references = @{ $configHash->{ "crossReferences" } };

  # Array for fields that go in <additional_fields> element.
  my @additional_fields = @{ $configHash->{ "additionalFields" } };

  # A description of Atlas. This will go at the top of the XML.
  my $atlasDescription = $configHash->{ "atlasDescription" };

  # Filename for differential XML dump.
  my $differentialDataFilename = $configHash->{ "differentialDataFilename" };

  # Filename for baseline XML dump.
  my $baselineDataFilename = $configHash->{ "baselineDataFilename" };

  # Files to write XML to.
  # Differential data.
  my $differentialEBeyeXML = IO::File->new(">$differentialDataFilename");
  # Baseline data.
  my $baselineEBeyeXML = IO::File->new(">$baselineDataFilename");

  # New XML writers with newlines and nice indentation.
  # Differential one.
  my $differentialWriter = XML::Writer->new(OUTPUT => $differentialEBeyeXML, DATA_MODE => 1, DATA_INDENT => 4, ENCODING => 'utf-8');
  # Baseline one.
  my $baselineWriter = XML::Writer->new(OUTPUT => $baselineEBeyeXML, DATA_MODE => 1, DATA_INDENT => 4, ENCODING => 'utf-8');

  # Today's date
  my $date_string = $configHash->{ "today" };

  # Begin XML
  foreach my $writer ($differentialWriter, $baselineWriter) {
    $writer->xmlDecl("UTF-8");
    $writer->startTag("database");
    $writer->dataElement("name" => "ExpressionAtlas");
    $writer->dataElement("description" => $atlasDescription);
    $writer->emptyTag("release");
    $writer->dataElement("release_date" => $date_string);
    $writer->dataElement("entry_count" => "ENTRY_COUNT_PLACEHOLDER");
    $writer->startTag("entries");
  }

  # Go through each species' gene TSV file.
  foreach my $species ( keys %{ $speciesToGeneTSVfiles } ) {
    my $geneFile = $speciesToGeneTSVfiles->{ $species };

    # Get the NCBI taxonomy ID for this species.
    my $taxid = get_tax_id( $species, $configHash->{ "ncbiTaxUri" } );

    # Make species name for description.
    my $speciesForDescription = make_description_species( $species );

    # Log the file we're reading.
    $logger->info( "Reading $geneFile..." );

    # Write one entry for each gene.
    # Open the file, there is one line per gene (== entry).
    open(my $geneFH, "<", $geneFile)
      or $logger->logdie( "Can't open \"$geneFile\": $!" );
    # Get the header and split into an array -- the column headings are the names
    # of the cross_references or additional_fields in the XML.
    my $header = <$geneFH>;
    chomp $header;
    my @A_colnames = split "\t", $header;

    # Loop through file...
    while(defined(my $line = <$geneFH>)) {
      # Ref to hash to store heading-value pairs.
      my $H_geneInfo = {};

      # remove newline.
      chomp $line;

      # Split on tabs.
      my @A_line = split "\t", $line;

      # Counter for array indices, to match to column headings.
      my $c = 0;
      # Put all the values from this line into the $H_geneInfo hash.
      foreach my $value (@A_line) {
        # Get column heading from the @A_colnames array.
        $H_geneInfo->{ $A_colnames[$c] } = $value;
        # Increment array index counter.
        $c++;
      }

      # If there is no "symbol" entered for this gene, use the value for
      # "ensgene" or "wbpsgene" -- this is Ensembl or WBPS gene ID and
      # will always be present.  Seems that sometimes the "symbol" is a
      # blank character and sometimes it doesn't exist at all, so we have
      # to check for both of these cases.
      if(!exists($H_geneInfo->{ "symbol" }) || $H_geneInfo->{ "symbol" } !~ /\w+/) {

        if( $H_geneInfo->{ "ensgene" } ) {
            $H_geneInfo->{ "symbol" } = $H_geneInfo->{ "ensgene" };
        }
        elsif( $H_geneInfo->{ "wbpsgene" } ) {
            $H_geneInfo->{ "symbol" } = $H_geneInfo->{ "wbpsgene" };
        }
        else { $logger->logdie( "No gene ID found for $species!" ); }
      }

      # Variable for Ensembl gene ID, just to make code easier to read later
      # on.
      my $geneID;
      if( $H_geneInfo->{ "ensgene" } ) {
        $geneID = $H_geneInfo->{ "ensgene" };
      }
      elsif( $H_geneInfo->{ "wbpsgene" } ) {
        $geneID = $H_geneInfo->{ "wbpsgene" };
      }
      else {
         $logger->logdie( "No gene ID found for $species!" );
      }

      # Number of differential experiments for this gene.
      my $differentialExptCount = (keys %{ $H_geneIDs2expts2contrasts->{ $geneID } });
      # Number of baseline experiments for this gene.
      my $baselineExptCount = (keys %{ $H_geneIDs2expts2assayGroups->{ $geneID } });

      if( $differentialExptCount ) {

        begin_gene_xml( $differentialWriter, $H_geneInfo, $taxid );

        # Now add the cross_references.
        # Add info from database.
        # Differential cross references
        if(exists($H_geneIDs2expts2contrasts->{ $geneID })) {
          # Get the experiment accessions for this gene.
          foreach my $exptAcc (keys %{ $H_geneIDs2expts2contrasts->{ $geneID } }) {
            # Write accessions to XML.
            $differentialWriter->emptyTag("ref", "dbname" => "atlas", "dbkey" => $exptAcc);
          }
        }

        add_shared_cross_references( $differentialWriter, \@cross_references, $H_geneInfo );

        # Get unique factor-factor value pairs.
        my $H_differentialFactors2values = make_factors_2_values($geneID, $H_geneIDs2expts2contrasts, $H_expts2contrasts2tests);

        # Add Atlas factors and values.
        foreach my $factor (keys %{ $H_differentialFactors2values }) {
          foreach my $value (keys %{ $H_differentialFactors2values->{ $factor } }) {
            $differentialWriter->dataElement("field" => $value, "name" => $factor);
          }
        }

        add_shared_additional_fields( $differentialWriter, \@additional_fields, $H_geneInfo );

        my $diffDesc = begin_description( $speciesForDescription, $H_geneInfo );

        $diffDesc .= " is differentially expressed in $differentialExptCount experiment(s); ";

        # Empty array to store string for each factor and its values, e.g.:
        # "compound: ozone 500 parts per billion,  phytoprostane A1 75 micromolar"
        my @factorValueStrings = ();
        # Go through the hash of factors and values...
        foreach my $factor (keys %{ $H_differentialFactors2values }) {
          # Get the factor name.
          my $factorValueString = "$factor: ";
          # Get all the factor values and append them to the above string
          # separated by commas.
          $factorValueString .= (join ", ", keys %{ $H_differentialFactors2values->{ $factor }});
          # Add this string to the array.
          push @factorValueStrings, $factorValueString;
        }
        # Join the factor and value strings with "; ".
        my $joinedFactorsValues = join "; ", @factorValueStrings;

        # Add differential description element.
        $differentialWriter->dataElement("description" => $diffDesc);

        # Close the entry elements.
        $differentialWriter->endTag("entry");
      }

      if( $baselineExptCount ) {

        begin_gene_xml( $baselineWriter, $H_geneInfo, $taxid );

        # Baseline cross references
        if(exists($H_geneIDs2expts2assayGroups->{ $geneID })) {
          # Get the experiment accessions for this gene.
          foreach my $exptAcc (keys %{ $H_geneIDs2expts2assayGroups->{ $geneID } }) {
            # Write accessions to XML.
            $baselineWriter->emptyTag("ref", "dbname" => "atlas", "dbkey" => $exptAcc);
          }
        }

        add_shared_cross_references( $baselineWriter, \@cross_references, $H_geneInfo );

        # Get unique factor-factor value pairs.
        my $H_baselineFactors2values = make_factors_2_values($geneID, $H_geneIDs2expts2assayGroups, $H_expts2assayGroups2factors);
        # Add Atlas factors and values.
        foreach my $factor (keys %{ $H_baselineFactors2values }) {
          foreach my $value (keys %{ $H_baselineFactors2values->{ $factor } }) {
            $baselineWriter->dataElement("field" => $value, "name" => $factor);
          }
        }

        add_shared_additional_fields( $baselineWriter, \@additional_fields, $H_geneInfo );

        my $baselineDesc = begin_description( $speciesForDescription, $H_geneInfo);

        $baselineDesc .= " is expressed in $baselineExptCount baseline experiment(s); ";

        # Empty array to store string for each factor and its values, e.g.:
        # "organism part: heart, liver"
        my @factorValueStrings = ();
        # Go through the hash of factors and values...
        foreach my $factor (keys %{ $H_baselineFactors2values }) {
          # Get the factor name.
          my $factorValueString = "$factor: ";
          # Get all the factor values and append them to the above string
          # separated by commas.
          $factorValueString .= (join ", ", keys %{ $H_baselineFactors2values->{ $factor }});
          # Add this string to the array.
          push @factorValueStrings, $factorValueString;
        }
        # Join the factor and value strings with "; ".
        my $joinedFactorsValues = join "; ", @factorValueStrings;

        # Add baseline description element
        $baselineWriter->dataElement("description" => $baselineDesc);

        $baselineWriter->endTag("entry");
      }
    }
  }

  # Close entries and database elements for both writers.
  foreach my $writer ($differentialWriter, $baselineWriter) {
    $writer->endTag("entries");
    $writer->endTag("database");
    $writer->end();
  }

  # Close files.
  $differentialEBeyeXML->close();
  $baselineEBeyeXML->close();

  # Log that we're done.
  $logger->info( "Differential Expression Atlas EB-eye data exported to $differentialDataFilename" );
  $logger->info( "Baseline Expression Atlas EB-eye data exported to $baselineDataFilename" );
}

# Add gene ID, symbol, and start cross_references element.
sub begin_gene_xml {

  my ( $writer, $H_geneInfo, $taxid ) = @_;

  # Start the entry, adding the gene ID.
  if( $H_geneInfo->{ "ensgene" } ) {
    $writer->startTag("entry", "id" => $H_geneInfo->{ "ensgene" });
  }
  elsif( $H_geneInfo->{ "wbpsgene" } ) {
    $writer->startTag("entry", "id" => $H_geneInfo->{ "wbpsgene" });
  }
  # Add the symbol as the name.
  $writer->dataElement("name" => $H_geneInfo->{ "symbol" });

  # Begin cross_references element.
  $writer->startTag("cross_references");

  # Add the NCBI taxonomy ID.
  $writer->emptyTag( "ref", "dbname" => "taxonomy", "dbkey" => $taxid );
}


# Add the rest of the cross references, close the cross_references
# element and begin the additional_fields one.
sub add_shared_cross_references {

  my ( $writer, $cross_references, $H_geneInfo ) = @_;

  # Add the rest of them.
  foreach my $dbname (@{ $cross_references }) {
    # Look for the database in this gene's information.
    if(exists($H_geneInfo->{ $dbname })) {
      # Split on "@@" in case there is more than one value for this database.
      my @refs = split "@@", $H_geneInfo->{ $dbname };
      # Add the ref(s) to the XML.
      foreach my $ref (@refs) {
        $writer->emptyTag("ref", "dbname" => $dbname, "dbkey" => $ref);
      }
    }
  }

  # Close cross_references element.
  $writer->endTag("cross_references");

  # Fill in the additional_fields.
  # Begin element.
  $writer->startTag("additional_fields");
}


# Add the rest of the additional_fields elements.
sub add_shared_additional_fields {

  my ( $writer, $additional_fields, $H_geneInfo ) = @_;

  foreach my $field (@{ $additional_fields }) {
    # Look for the field in this gene's information.
    if(exists($H_geneInfo->{ $field })) {
      # Split on "@@" in case of multiple values.
      my @values = split "@@", $H_geneInfo->{ $field };
      # Add the value(s) to the XML.
      foreach my $value (@values) {
        $writer->dataElement("field" => $value, "name" => $field);
      }
    }
  }

  # Close the additional_fields element.
  $writer->endTag("additional_fields");
}


sub begin_description {

  my ( $speciesForDescription, $H_geneInfo ) = @_;

  # The first part should be the "symbol" -- this will be the Ensembl gene ID if no "symbol" is present.
  my $xmlDescription = $speciesForDescription . " " . $H_geneInfo->{ "symbol" };

  # Add the "description" if there is one.
  # First check if there is one,
  if(exists($H_geneInfo->{ "description" })) {
    # If there is one, it could be blank, so check if it contains any characters.
    if($H_geneInfo->{ "description" } =~ /\w+/) {
      $xmlDescription .= ", ".$H_geneInfo->{ "description" }.",";
    }
  }
  return $xmlDescription;
}


# get_and_write_experiments_info
#   - Retrieve differential and baseline experiments information from Atlas
#   database and write it to XML dump files (differential to one, baseline to
#   another).
sub get_and_write_experiments_info {
  my ($configHash) = @_;

  # Connect to Atlas database.
  my $atlasDB = connect_pg_atlas;

  # Run the queries to create two hashes, one with info for baseline
  # experiments and one with info for differential experiments.
  my $H_differentialExperimentsInfo = $atlasDB->fetch_differential_experiment_info_from_atlasdb( $logger );
  my $H_baselineExperimentsInfo = $atlasDB->fetch_baseline_experiment_info_from_atlasdb( $logger );

  # populate $H_differentialExperimentsInfo with experiment titles for each differential study
  foreach my $expAcc ( keys %{ $H_differentialExperimentsInfo } ) {
    my $title = fetch_experiment_title_from_webapi( $expAcc, $logger );
    $H_differentialExperimentsInfo->{ $expAcc }->{ "title" } = $title;
  } 

  # populate $H_differentialExperimentsInfo with experiment titles for each baseline study
  foreach my $expAcc ( keys %{ $H_baselineExperimentsInfo } ) {
    my $title = fetch_experiment_title_from_webapi( $expAcc, $logger );
    $H_baselineExperimentsInfo->{ $expAcc }->{ "title" } = $title;
  } 

  # Disconnect from Atlas DB.
  $atlasDB->get_dbh->disconnect;

  # Files to write XML to.
  # Differential experiments.
  my $differentialExperimentsFilename = $configHash->{ "differentialExperimentsFilename" };
  my $differentialExperimentsEBeyeXML = IO::File->new(">$differentialExperimentsFilename");
  # Baseline data.
  my $baselineExperimentsFilename = $configHash->{ "baselineExperimentsFilename" };
  my $baselineExperimentsEBeyeXML = IO::File->new(">$baselineExperimentsFilename");

  # A description of Atlas. This will go at the top of the XML.
  my $atlasDescription = $configHash->{ "atlasDescription" };

  # New XML writers with newlines and nice indentation.
  # Differential one.
  my $differentialExperimentsWriter = XML::Writer->new(OUTPUT => $differentialExperimentsEBeyeXML, DATA_MODE => 1, DATA_INDENT => 4);
  # Baseline one.
  my $baselineExperimentsWriter = XML::Writer->new(OUTPUT => $baselineExperimentsEBeyeXML, DATA_MODE => 1, DATA_INDENT => 4);

  # Today's date.
  my $date_string = $configHash->{ "today" };

  # Begin XML
  foreach my $writer ($differentialExperimentsWriter, $baselineExperimentsWriter) {
    $writer->xmlDecl("UTF-8");
    $writer->startTag("database");
    $writer->dataElement("name" => "ExpressionAtlas");
    $writer->dataElement("description" => $atlasDescription);
    $writer->emptyTag("release");
    $writer->dataElement("release_date" => $date_string);
  }

  # Count the number of experiments for each type.
  my $differentialExperimentsCount = (keys %{ $H_differentialExperimentsInfo });
  $differentialExperimentsWriter->dataElement("entry_count" => $differentialExperimentsCount);
  my $baselineExperimentsCount = (keys %{ $H_baselineExperimentsInfo });
  $baselineExperimentsWriter->dataElement("entry_count" => $baselineExperimentsCount);

  # Start the "entries" element.
  foreach my $writer ($differentialExperimentsWriter, $baselineExperimentsWriter) {
    $writer->startTag("entries");
  }

  # Write the differential experiments info.
  add_experiments_info($differentialExperimentsWriter, $H_differentialExperimentsInfo);
  # Write the baseline experiments info.
  add_experiments_info($baselineExperimentsWriter, $H_baselineExperimentsInfo);

  # Close entries and database elements for both writers.
  foreach my $writer ($differentialExperimentsWriter, $baselineExperimentsWriter) {
    $writer->endTag("entries");
    $writer->endTag("database");
    $writer->end();
  }

  # Close files.
  $differentialExperimentsEBeyeXML->close();
  $baselineExperimentsEBeyeXML->close();

  # Log that we're done.
  $logger->info( "Differential Expression Atlas EB-eye experiments info exported to $differentialExperimentsFilename" );
  $logger->info( "Baseline Expression Atlas EB-eye experiments info exported to $baselineExperimentsFilename" );
}


# get_contrast_assaygroup_details
#   - Download and parse contrastdetails.tsv and assaygroupdetails.tsv, put
#   useful data into hashes.
#   - contrastdetails.tsv contains (among other things) accessions, contrast IDs, and
#   test factors and their values for each contrast in Atlas.
#  - assaygroupdetails.tsv contains accessions, assay group IDs, and factors and
#   their values for each assay group in Baseline Atlas.
#   - Build hashes like:
#     $H_expts2contrasts2tests->{ <experiment accession> }->{ <contrast ID> }->{ <test factor type> } = <test factor value>
#     $H_expts2assayGroups2factors->{ <experiment accession> }->{ <assay group ID> }->{ <factor type> } = <factor value>
sub get_contrast_assaygroup_details {

  # Ref to hash with config.
  my ($contrastdetailsURL, $assaygroupdetailsURL) = @_;

  # Download contrastdetails.tsv and assaygroupdetails.tsv.
  my $allContrastDetails = get_atlas_contrast_details;

  # Go through it and create the hash with experiment accessions, contrast
  # IDs, and test factor types and values.
  my $H_expts2contrasts2tests = {};

  foreach my $contrastDetails ( @{ $allContrastDetails } ) {

    my $exptAcc = $contrastDetails->get_exp_acc;
    my $contrastID = $contrastDetails->get_contrast_id;
    my $testFactors = $contrastDetails->get_factors->{ "test" };

    foreach my $type ( keys %{ $testFactors } ) {

      $H_expts2contrasts2tests->{ $exptAcc }->{ $contrastID }->{ $type } = $testFactors->{ $type };
    }
  }


  # Download assay groups details file.
  my $assaygroupdetails = download_atlas_details($assaygroupdetailsURL);

  # Parse assay group details.
  # Split on newlines.
  my @assaygroupdetails = split "\n", $assaygroupdetails;

  # Go through and create hash with experimetn accessions, assay group IDs, factor types and their values.
  my $H_expts2assayGroups2factors = {};

  foreach my $line (@assaygroupdetails) {

    # Split the line on tabs.
    my @splitLine = split "\t", $line;

    # We just want the factor lines, so skip the other lines.
    # factor/characteristic is element 2.
    unless($splitLine[2] eq "factor") { next };

    # If we're still here this must be a factor line, so save the details to the hash.
    my $exptAcc = $splitLine[0];
    my $assayGroupID = $splitLine[1];
    my $factor = $splitLine[3];
    my $value = $splitLine[4];

    $H_expts2assayGroups2factors->{ $exptAcc }->{ $assayGroupID }->{ $factor } = $value;
  }

  # Return the newly created hashes.
  return ($H_expts2contrasts2tests, $H_expts2assayGroups2factors);
}

# download_atlas_details
#   - Take URL, download with LWP::Simple get function, and return variable
#   containing downloaded data.
sub download_atlas_details {
  my ($url) = @_;
  # Log what we're downloading.
  $logger->info( "Downloading $url ..." );
  # Download using LWP::Simple get function.
  my $details = get $url;
  # Die if the get didn't work.
  $logger->logdie( "Could not get $url" ) unless defined $details;
  # If we're still alive, it did work, so log that we got the contrast details successfully.
  $logger->info( "Download successful." );
  return $details;
}

# Simple routine that returns public or private

sub get_privacy{
  
  my ( $expId ) =  @_;

  if ( ! exists $exptPrivacies->{ $expId } ){
    my $url = "http://peach.ebi.ac.uk:8480/api/privacy.txt?acc=$expId";
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($url)->content;
    my ($privacy) = $response =~ m/privacy:(\w+)\s/g;

    if (! $privacy ){
      $privacy='unknown';
    }
    elsif ($privacy ne 'public' && $privacy ne 'private'){
      $logger->logdie( "Invalid privacy \"$privacy\" for \"$expId\"" );
    }
    $exptPrivacies->{ $expId } = $privacy;
  }
  return $exptPrivacies->{ $expId };
}

# make_factors_2_values
#   - Here get the (unique) factor-factor value pairs for this gene by
#   joining info from the database (in $H_geneIDs2expts2contrasts or $H_geneIDs2expts2assayGroups) and
#   from the contrastdetails.tsv file (in $H_expts2contrasts2tests or $H_expts2assayGroups2factors).
#   - This info is used both in the <additional_fields> element and the
#   <description> element so just get it out in one place here.
#   - Build a hash like:
#   $H_factors2values->{ <factor> }->{ <value> } = 1
#   - This way if we have a few experiments studying the same factor value
#   and this gene was expressed/DE in all of them, we won't report this factor value
#   multiple times.
sub make_factors_2_values {
  my ($geneID, $H_geneIDs2expts2atlasIDs, $H_expts2atlasIDs2factors) = @_;

  my $H_factors2values = {};

  if(exists($H_geneIDs2expts2atlasIDs->{ $geneID })) {
    # Go through the accessions for this gene.
    foreach my $exptAcc (keys %{ $H_geneIDs2expts2atlasIDs->{ $geneID } }) {

      # FIXME: Skip proteomics for now.
      if( $exptAcc =~ /^E-PROT/ ) { next; }

      # Go through the IDs.
      foreach my $atlasID (@{ $H_geneIDs2expts2atlasIDs->{ $geneID }->{ $exptAcc }}) {
        # If the accession exists in the $H_expts2atlasIDs2factors hash ...
        if(exists($H_expts2atlasIDs2factors->{ $exptAcc })) {
          # Check that the ID exists in $H_expts2atlasIDs2factors
          unless(exists($H_expts2atlasIDs2factors->{ $exptAcc }->{ $atlasID })) {
            if (! exists $atlasIDMissing->{ $exptAcc }->{ $atlasID }){
                $logger->warn( "ID $atlasID in experiment $exptAcc found in database but not in Atlas details file." );
                $atlasIDMissing->{$exptAcc}->{ $atlasID } = 1;
            }
            next;
          }

          # Using the experiment accession and ID, get the test factor and value.
          foreach my $factor (keys %{ $H_expts2atlasIDs2factors->{ $exptAcc }->{ $atlasID } }) {
            my $value = $H_expts2atlasIDs2factors->{ $exptAcc }->{ $atlasID }->{ $factor };
            # Add them to $H_factors2values.
            if( $value ) {
              $H_factors2values->{ $factor }->{ $value } = 1;
            }
          }
        }
        # If the accession doesn't exist in the
        # $H_expts2atlasIDs2factors hash, something odd is going on.
        # Log the accession and die.
        else {
          if (! exists $contrastDetailsMissing->{ $exptAcc }){
            my $privacy = get_privacy( $exptAcc );
            my $msg = "$exptAcc found in database but not found in Atlas details file.";
   
            # If exp is private don't error- that is the reason it's missing.
 
            if ($privacy eq 'public'){
              $logger->warn( "$msg" );
            }
            elsif ($privacy eq 'unknown'){
              $logger->warn( "$msg Privacy status for this experiment is unknown- has it been withdrawn?");
            } 
            $contrastDetailsMissing->{$exptAcc} = $privacy;
          }
          next;
        }
      }
    }
  }

  return $H_factors2values;
}

# add_experiments_info
#   - Write XML using experiments info from Atlas database.
sub add_experiments_info {
  my ($writer, $H_experimentsInfo) = @_;

  foreach my $exptAcc (keys %{ $H_experimentsInfo }) {
    # Start the entry for this experiment.
    # Add the accession as the "id".
    $writer->startTag("entry", "id" => $exptAcc);

    # Add the accession as the "name".
    $writer->dataElement("name" => $exptAcc);

    # Add the title as the "description".
    $writer->dataElement("description" => $H_experimentsInfo->{ $exptAcc }->{ "title" });

    # Add the date as "creation" date, "last_modification" and publication" date.
    $writer->startTag("dates");

    # format datefield to exclude any time stamps and retain only date
    my $dateformat=(split /\s+/, $H_experimentsInfo->{ $exptAcc }->{ "date" })[0];

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


sub get_tax_id {
  my ( $species, $uri ) = @_;

  # Rice-specific tweak. If the species is oryza_sativa, change to
  # oryza_sativa_japonica_group because that's the one whose IDs we use.
  if( $species eq "oryza_sativa" ) {
    $species .= "_japonica_group";
  }

  ## No NCBI taxonomy ID exist for species named oryza_indica as in Ensembl
  ## using oryza_sativa_indica_group
  elsif( $species eq "oryza_indica" ) {
    $species = "oryza_sativa_indica_group";
  }

  # Make the species-specific URI.
  my $speciesUri = $uri . $species;

  my $userAgent = LWP::UserAgent->new;
  $userAgent->env_proxy;
  my $request = HTTP::Request->new(
    GET => $speciesUri
  );
  $request->header( 'Accept' => 'application/xml' );

  $logger->info( "Querying NCBI for taxonomy ID of species \"$species\"..." );

  my $response = $userAgent->request( $request );

  my $numRetries = 0;
  while( $numRetries < 3 && ! $response->is_success ) {
    $logger->warn( "Query unsuccessful: ", $response->status_line, ", retrying..." );
    $response = $userAgent->request( $request );
    $numRetries++;
  }

  unless( $response->is_success ) {
    $logger->logdie(
      "Maximum number of retries reached. Service appears unresponsive (".
      $response->status_line,
      ")."
    );
  }
  else {
    $logger->info( "Query successful" );
  }

  # Get the XML from NCBI.
  my $resultXMLstring = $response->decoded_content;

  # Parse the XML.
  my $parsedXML = XMLin(
    $resultXMLstring,
    ForceArray => [
      'Id',
      'TermSet',
    ],
    KeyAttr => {
      TermSet => 'Term',
    }
  );

  # Get the ID. There should only be one but there could be more and they
  # come in an array.
  my $idArray = $parsedXML->{ "IdList" }->{ "Id" };

  # Check that there's exactly one ID, die if not.
  if( !$idArray ) {
    $logger->logdie( "No NCBI taxonomy ID found for species \"$species\", cannot continue." );
  }
  elsif( @{ $idArray } > 1 ) {
    $logger->logdie( "More than one NCBI taxonomy ID found for species \"$species\", cannot continue." );
  }
  else {
    my ( $id ) = @{ $idArray };

    return $id;
  }
}

sub make_description_species {
  my ( $species ) = @_;

  $species = ucfirst( $species );

  $species =~ s/_/ /g;

  if( $species eq "Oryza sativa" ) {
    $species .= " Japonica Group";
  }

  elsif( $species eq "Oryza indica" ) {
    $species = "Oryza sativa Indica Group";
  }

  return $species;
}

sub add_entry_count {

  my ( $configHash ) = @_;

  my $differentialDataFilename = $configHash->{ "differentialDataFilename" };
  my $baselineDataFilename = $configHash->{ "baselineDataFilename" };

  foreach my $xmlFile ( $differentialDataFilename, $baselineDataFilename ) {

    $logger->info( "Adding entry count for $xmlFile..." );

    my $entryCount = `grep "<entry id=" $xmlFile | wc -l`;
    chomp $entryCount;

    `perl -pi -e 's/ENTRY_COUNT_PLACEHOLDER/$entryCount/;' $xmlFile`;

    $logger->info( "Entry count added." );
  }
}
