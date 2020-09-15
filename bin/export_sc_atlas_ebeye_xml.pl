#!/usr/bin/env perl
## export WEB_API_URL="https://wwwdev.ebi.ac.uk/gxa/sc/json/experiments"

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
	log4perl.rootlogger					= INFO, LOG1, SCREEN
	log4perl.appender.SCREEN			= Log::Log4perl::Appender::Screen
	log4perl.appender.SCREEN.stderr		= 0
	log4perl.appender.SCREEN.layout		= Log::Log4perl::Layout::PatternLayout
	log4perl.appender.SCREEN.layout.ConversionPattern = %-5p - %m%n
	log4perl.appender.LOG1				= Log::Log4perl::Appender::File
	log4perl.appender.LOG1.filename		= sub { get_log_file_name( "export_atlas_ebeye_xml" ) }
	log4perl.appender.LOG1.header_text	= sub { get_log_file_header( "Atlas EB-eye XML dump" ) }
	log4perl.appender.LOG1.mode			= append
	log4perl.appender.LOG1.layout		= Log::Log4perl::Layout::PatternLayout
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

	# A description of Atlas. This will go at the top of the XML.
	atlasDescription => "A semantically enriched database of publicly available single cell gene and transcript expression data. The data is re-analysed in-house to detect genes showing interesting baseline expression patterns under the conditions of the original experiment.",

};


my $H_baselineExperimentsInfo = fetch_experiments_info_from_webapi($logger);


# Get info from webAPI and write XMLs for baseline experiment info.
get_and_write_experiments_info($configHash, $H_baselineExperimentsInfo);


## fetch json formatted result for experiments and its titles from WebAPI.
sub fetch_experiments_info_from_webapi {

    my ( $logger ) = @_;

    my $url = $ENV{'WEB_API_URL'};

    my $json_hash;

    my $abs_url = join("/",$url);
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
# 	- Retrieve differential and baseline experiments information from Atlas
# 	database and write it to XML dump files (differential to one, baseline to
# 	another).
sub get_and_write_experiments_info {
	my ($configHash, $H_baselineExperimentsInfo) = @_;

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
	add_experiments_info($baselineExperimentsWriter, $H_baselineExperimentsInfo);

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
# 	- Write XML using experiments info from Atlas database.
sub add_experiments_info {
	my ($writer, $H_experimentsInfo) = @_;

	foreach my $hash_ref ( @{ $H_baselineExperimentsInfo->{'experiments'} } ){
 		my $exptAcc = $hash_ref->{'experimentAccession'};

		# Start the entry for this experiment.
		# Add the accession as the "id".
		$writer->startTag("entry", "id" => $exptAcc);

		# Add the accession as the "name".
		$writer->dataElement("name" => $exptAcc);

		# Add the title as the "description".
		$writer->dataElement("description" => $hash_ref->{ "experimentDescription" });

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