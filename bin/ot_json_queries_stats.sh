#!/bin/bash

set -euo pipefail

scriptDir=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usageMessage="Usage: (-j cttv010-2018-09-25.json.gz) (-o outputPath)"

while getopts ":j:o:" opt; do
  case $opt in
    j)
      jsonDump=$OPTARG;
      ;;
    o)
      outputPath=$OPTARG;
      ;;
    ?)
      echo "Unknown option: $OPTARG"
      echo $usageMessage
      exit 2
      ;;
  esac
done

echo "Json file: $jsonDump"
echo "Output path: $outputPath"

file_name=$(basename $jsonDump | sed 's/[.].*//')

json_dump_stats(){
  json_file=$1
  outputPath=$2

  file_name=$(basename $json_file | sed 's/[.].*//')

  # retrieve evidences
  cat $json_file | jq '.evidence.unique_experiment_reference' | sort  > $outputPath/${file_name}_experiments.txt

  # number of microarray that has probe id field.
  cat $json_file | jq '.unique_association_fields | select( has("probe_id"))' | grep "study_id"  \
     | grep  -oe 'E-[[:upper:]]*-[[:digit:]]*' | sort -u > $outputPath/${file_name}_micoarray.txt

  # log fold change of each evidence.
  cat $json_file | jq '.evidence.log2_fold_change.value' >  $outputPath/${file_name}_log_fold_changes.txt

  # pvalues of each evidence.
  cat $json_file | jq '.evidence.resource_score.value' >  $outputPath/${file_name}_pvalue.txt

  # tabulate contrast experiments and genes associated with each study.
  cat $json_file | jq '.unique_association_fields | .comparison_name + "  " + .study_id + "  " + .geneID' > $outputPath/${file_name}_contrast_exp_gene.txt

  file_contrast=$outputPath/${file_name}_contrast_exp_gene.txt
  exp=$(cat $file_contrast | awk -F"  " '{print $2}' | grep  -oe 'E-[[:upper:]]*-[[:digit:]]*' | sort -u)
  for expAcc in $exp; do
    contrast=$(cat $file_contrast | grep "$expAcc" | awk -F"  " '{print $1}' | sort -u)
    for cont in $(echo -e $contrast | tr "\"" "\n" | sed '/^$/d'); do
      ngenes=$(cat $file_contrast | grep "$expAcc" | grep -F "$cont" | wc -l)
      echo -e "$expAcc\t$cont\t$ngenes"
    done
  done
}

IFS="
"

echo "Running json dump stats .."
json_dump_stats $jsonDump $outputPath > $outputPath/${file_name}_report.txt

echo "sorting report .."
cat $outputPath/${file_name}_report.txt | sort -t$'\t' -k3 -nr > $outputPath/${file_name}_report_sort.txt

echo "Plots for sanity .."
"$scriptDir/ot_json_evidence_plots.R" -i $outputPath/${file_name}_experiments.txt -l $outputPath/${file_name}_log_fold_changes.txt -p $outputPath/${file_name}_pvalue.txt -o $outputPath
