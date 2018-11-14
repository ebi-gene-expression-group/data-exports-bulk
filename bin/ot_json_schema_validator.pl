#!/usr/bin/env perl
# Copied from: https://github.com/opentargets/json_schema/blob/master/scripts/json_schema_validator.pl
# Validate submission records line by line.
# Stdout: correct submission records
# Stderr: submission errors, warnings
# Usage: cat submissions-file.json | ./json_schema_validator.pl <schema url or file> > validated-file.json
# PRO TIP: export JSON_VALIDATOR_DEBUG=1 to get the internal validator logs
use strict;
use warnings;
use JSON;
use JSON::Validator 0.95; # we're affected by https://github.com/jhthorsen/json-validator/issues/59
use Carp qw( croak );
use Text::Trim qw(trim);
use File::Basename;
use File::Slurp;
use Getopt::Long;

my $schemaUri;
my $stamp = 0;
GetOptions ("schema=s"   => \$schemaUri,
            "add-validation-stamp"  => \$stamp);

croak "Usage: ./json_schema_validator.pl --schema <schema url or file> [--add-validation-stamp] \n" unless defined $schemaUri;

my $validator = JSON::Validator->new;
$validator->schema($schemaUri);

my $schema_version = $validator->schema->data->{'version'};

my $err_count = 0;

while(<STDIN>){
   my $record = from_json($_);
   if($stamp) {
     $record->{'validated_against_schema_version'} = $schema_version;
   }

   my @errors = $validator->validate($record);

   if(@errors){
      print STDERR ("Bad record: " . trim($_) ."\t" );
      print STDERR ($_->{path} .": ". $_->{message} ."\t")  foreach @errors;
      print STDERR "\n" ;
      $err_count++;
   } else {
     print STDOUT to_json($record) ."\n" ;
   }
   if($err_count > 1000){
     croak "Too many errors. Giving up";
   }
}

if($err_count>0){
   croak "Exited with $err_count invalid records";
}
