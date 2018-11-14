#!/usr/bin/env perl
#

use strict;
use warnings;
use 5.10.0;

use Log::Log4perl;
use XML::Writer;
use IO::File;
use URI::Split qw(
	uri_split
);
use DateTime;

# Atlas common subroutines.
use Atlas::Common qw(
	connect_pg_atlas
	create_atlas_site_config
	get_atlas_contrast_details
	get_log_file_header
	get_log_file_name
);

use EBI::FGPT::Config qw($CONFIG);

$| = 1;

my $logger_config = q(
	log4perl.rootlogger					= INFO, LOG1, SCREEN
	log4perl.appender.SCREEN			= Log::Log4perl::Appender::Screen
	log4perl.appender.SCREEN.stderr		= 0
	log4perl.appender.SCREEN.layout 	= Log::Log4perl::Layout::PatternLayout
	log4perl.appender.SCREEN.layout.ConversionPattern = %-5p - %m%n
	log4perl.appender.LOG1				= Log::Log4perl::Appender::File
	log4perl.appender.LOG1.filename		= sub { get_log_file_name( "export_atlas_chebi_xml" ) }
	log4perl.appender.LOG1.header_text	= sub { get_log_file_header( "Atlas ChEBI XML dump" ) }
	log4perl.appender.LOG1.mode			= append
	log4perl.appender.LOG1.layout		= Log::Log4perl::Layout::PatternLayout
	log4perl.appender.LOG1.layout.ConversionPattern = %-5p - %m%n
);

# Initialise logger.
Log::Log4perl::init( \$logger_config );
my $logger = Log::Log4perl::get_logger;

# Download all the contrast details from Atlas.
my $allContrastDetails = get_atlas_contrast_details;

# Get all the ChEBI IDs used in Atlas contrasts, and the associated experiment
# accessions.
my $chebiId2expAccs = get_chebi_experiment_accessions( $allContrastDetails );

# Get the titles for those experiments from the Atlas database.
$logger->info("Using database connection ".$CONFIG->get_AE_PG_DSN()." for ArrayExpress... (see ArrayExpressSiteConfig.yaml file)." );
my $expAcc2title = get_experiment_titles_from_db( $chebiId2expAccs );

# Merge the hashes of ChEBI IDs and titles to create one hash mapping ChEBI IDs
# to experiment accessions and their titles..
my $chebiId2expAcc2title = {};
foreach my $chebiId ( keys %{ $chebiId2expAccs } ) {

	foreach my $expAcc ( keys %{ $chebiId2expAccs->{ $chebiId } } ) {

		my $title = $expAcc2title->{ $expAcc };

		# If we didn't get a title for this experiment, warn and skip.
		unless( $title ) {
			$logger->warn( "Did not find title for $expAcc in Atlas database." );
			next;
		}

		# Add the ChEBI ID, accession and title to the hash.
		$chebiId2expAcc2title->{ $chebiId }->{ $expAcc } = $title;
	}
}

# Write the XML report using the merged hash.
write_xml( $chebiId2expAcc2title );
# end
#####


#############
# SUBROUTINES

# Go through the contrast details and find contrasts with ChEBI IDs.
# Returns a hash mapping ChEBI IDs to the experiments they were found in.
sub get_chebi_experiment_accessions {

	my ( $allContrastDetails ) = @_;

	$logger->info( "Looking for contrasts containing ChEBI IDs..." );

	my $chebiId2expAccs = {};

	# Go through the contrast details ...
	foreach my $contrastDetails ( @{ $allContrastDetails } ) {

		# Get the experiment accession of this contrast.
		my $expAcc = $contrastDetails->get_exp_acc;

		# Get the characteristics and factors. ChEBI IDs quite unlikely to be
		# in characteristics, but we don't want to miss any.
		my $characteristics = $contrastDetails->get_characteristics;
		my $factors = $contrastDetails->get_factors;

		# Go through the characteristics and factors...
		foreach my $attributeHash ( $characteristics, $factors ) {

			# Assay group type is either "test" or "reference".
			foreach my $assayGroupType ( keys %{ $attributeHash } ) {

				# Go through the characteristic or factor types for this assay group...
				foreach my $type ( keys %{ $attributeHash->{ $assayGroupType } } ) {

					# Get the characteristic or factor value.
					my $value = $attributeHash->{ $assayGroupType }->{ $type };

					# Get the EFO URI(s) for this type-value pair in this contrast.
					my $efoUris = $contrastDetails->get_efo_uris( $type, $value );

					# Skip if we didn't get an EFO URI.
					next unless $efoUris;

                    # Go through the array of URIs returned...
                    foreach my $efoUri ( @{ $efoUris } ) {

                        # Skip if the EFO URI doesn't contain "CHEBI".
                        next unless $efoUri =~ /CHEBI/;

                        # Split the URI into parts.
                        my %parts;
                        @parts{ my @keys = qw( schema auth path query frag ) } = uri_split( $efoUri );

                        # The "path" is the bit after the domain in the URL. E.g.
                        # in "http://purl.obolibrary.org/obo/CHEBI_28262" the
                        # "path" is "obo/CHEBI_28262".
                        # Split the path on the "/".
                        my @splitPath = split "/", $parts{ "path" };

                        # The last element in the path is the ChEBI ID.
                        my $chebiId = pop @splitPath;

                        # Replace underscore in ChEBI ID with a colon.
                        $chebiId =~ s/_/:/;

                        # Add the ChEBI ID and experiment accession to the hash.
                        $chebiId2expAccs->{ $chebiId }->{ $expAcc } = 1;
                    }
				}
			}
		}
	}

	# Quit if we didn't find any ChEBI IDs.
	unless( keys %{ $chebiId2expAccs } ) {
		$logger->logdie( "No contrasts containing ChEBI IDs were found." );
	}

	$logger->info( "Successfully retrieved contrasts containing ChEBI IDs." );

	return $chebiId2expAccs;
}


# Query the Atlas database and get the titles for all the experiments we found
# containing ChEBI IDs.
# Return a hash mapping experiment accession to experiment title.
sub get_experiment_titles_from_db {

	my ( $chebiId2expAccs ) = @_;

    # Create a hash with experiment accessions as keys.
	my $expAccessions = {};

    foreach my $chebiID ( keys %{ $chebiId2expAccs } ) {

        foreach my $expAcc ( keys %{ $chebiId2expAccs->{ $chebiID } } ) {

            $expAccessions->{ $expAcc } = 1;
        }
    }

    # Experiment accessions are the keys of the new hash.
    my @expAccessions = keys %{ $expAccessions };

	# Create Atlas database connection.
	my $atlasDB = connect_pg_atlas;

    # Get the titles for the experiment accessions.
    my $expAcc2title = $atlasDB->fetch_experiment_titles_from_atlasdb( \@expAccessions, $logger );

    # Disconnect from Atlas DB.
    $atlasDB->get_dbh->disconnect;

	return $expAcc2title;
}


# Join all the accessions found in contrast details into a string ready for SQL
# query, e.g. "('E-MTAB-1234', 'E-GEOD-789')".
sub make_accession_string_for_query {

	my ( $chebiId2expAccs ) = @_;

	my $allAccessions = {};

	# Go through the ChEBI IDs...
	foreach my $chebiId ( keys %{ $chebiId2expAccs } ) {

		# Go through the accessions for this ChEBI ID...
		foreach my $expAcc ( keys %{ $chebiId2expAccs->{ $chebiId } } ) {

			# Add them to a hash of all accessions.
			$allAccessions->{ $expAcc } = 1;
		}
	}

	# Create an array of accessions in single quotes.
	my @quotedAccessions = map { "'$_'" } keys %{ $allAccessions };

	# Join the quoted accessions with commas.
	my $joinedAccessions = join ", ", @quotedAccessions;

	# Return the joined accessions inside parentheses.
	return "($joinedAccessions)";
}


# Write out the hash mapping ChEBI IDs to accessions and titles in XML.
sub write_xml {

	my ( $chebiId2expAcc2title ) = @_;

	# Filename for the output file.
	my $xmlOutputFile = "expression_atlas_chebi_report.xml";

	$logger->info( "Writing XML report to $xmlOutputFile..." );

	# Config for the header.
	my $dbName = "Expression Atlas";
	my $dbDesc = "A semantically enriched database of publicly available gene and transcript expression data. The data is re-analysed in-house to detect genes showing interesting baseline and differential expression patterns under the conditions of the original experiment.";
	my $linkUrl = "http://www.ebi.ac.uk/gxa/experiments/*";

	# File handle to write to.
	my $xmlOutput = IO::File->new( ">$xmlOutputFile" );

	# Set up XML writer.
	my $xmlWriter = XML::Writer->new(
		OUTPUT 		=> $xmlOutput,
		DATA_MODE	=> 1,
		DATA_INDENT	=> 4
	);

	# XML declaration.
	$xmlWriter->xmlDecl( "UTF-8" );

	# Begin the XML document.
	$xmlWriter->startTag( "doc" );
	$xmlWriter->dataElement( "database_name" => $dbName );
	$xmlWriter->dataElement( "database_description" => $dbDesc );
	$xmlWriter->dataElement( "link_url" => $linkUrl );
	$xmlWriter->startTag( "entities" );

	# Go through the ChEBI IDs...
	foreach my $chebiId ( keys %{ $chebiId2expAcc2title } ) {

		# Start entity element and add ChEBI ID.
		$xmlWriter->startTag( "entity" );

		$xmlWriter->dataElement( "chebi_id" => $chebiId );
		$xmlWriter->startTag( "xrefs" );

		# Go through experiment accessions for this ChEBI ID...
		foreach my $expAcc ( keys %{ $chebiId2expAcc2title->{ $chebiId } } ) {

			# Begin xref element and add accession and title.
			$xmlWriter->startTag( "xref" );
			$xmlWriter->dataElement( "display_id" => $expAcc );
			$xmlWriter->dataElement( "link_id" => $expAcc );

			my $title = $chebiId2expAcc2title->{ $chebiId}->{ $expAcc };
			$xmlWriter->dataElement( "name" => $title );

			# End xref element.
			$xmlWriter->endTag( "xref" );
		}

		# End xrefs and entity elements for this ChEBI ID.
		$xmlWriter->endTag( "xrefs" );
		$xmlWriter->endTag( "entity" );
	}

	# End the document.
	$xmlWriter->endTag( "entities" );
	$xmlWriter->endTag( "doc" );

	# Finish the document and validate.
	$xmlWriter->end;

	# Close the filehandle.
	$xmlOutput->close;

	$logger->info( "Successfully written XML report." );
}
