#!/usr/bin/env Rscript

# Author: Suhaib Mohammed

 ## parse study_list as `echo -e "E-MTAB-5214"'\t'"E-MTAB-513"'\t'"E-MTAB-2836"`
 ## study_type - tissues or cell_types

suppressMessages( library(funr) )
suppressMessages( library(EDASeq) )
suppressMessages( library(ggplot2) )
suppressMessages( library(ggfortify) )
suppressMessages( library(RUVSeq) )
suppressMessages( library(RColorBrewer) )

script_path<-funr::get_script_path()

## loading generic functions 
source(paste(script_path,"generic_functions.R",sep="/"))
source(paste(script_path,"get_data_from_staging.R",sep="/"))

# Get commandline arguments.
args <- commandArgs( TRUE )

if( length( args ) != 3 ) {
  stop( "\nUsage:\n\tscript.R <study_list> <tissues_or_cell_type> <output_path>\n\n" )
}

# Get the transcripts expression filename from the arguments.
study_list <- args[ 1 ]
study_type <- args[ 2 ]
output_path <- args[ 3 ]

study_list <- unlist(strsplit(study_list, split="\t"))
QUANTILE_THRESHOLD <- as.numeric(Sys.getenv('QUANTILE_THRESHOLD'))
LEASTVARGENES_THRESHOLD <- as.numeric(Sys.getenv('LEASTVARGENES_THRESHOLD'))

## get study_type expreriments from exression atlas
atlasData <- getAtlasData(c(study_list))

t<-atlasData
all <- matrix()

#################################################
for (i in names(t)) {
  expAcc <- i
  k <- t[[i]]
  exp <- k$rnaseq
  eCounts <- assays(exp)$counts
  samples<-colnames(eCounts)
  if ( study_type == "tissues" ){
    average.counts<-technical_replicate_average_gtex(exp,expAcc)
  } else if ( study_type == "cell_types" ){
    average.counts<-technical_replicate_average_bp(exp,expAcc,eCounts)
  }
    all <- as.matrix(mergeX(all,average.counts))
}
all <- all[,-1]

## sanity check 
colnames(all)
dim(all)

x<-sapply(strsplit(colnames(all),split="_"),"[",3)

dir.create(paste(output_path,study_type,sep="/"))

cat("Filtering for low expression signals..... \n\n")
## filtering low expression signals
  filter <- rowSums(all>10)>=15
  filtered <- all[filter,]
  if ( study_type == "cell_types" ){
      x<-as.factor(sapply(strsplit(colnames(filtered),split="_"),"[",3))
    }
  filterCols <- colSums(filtered == 0) / nrow(filtered) < 0.90
  x <- x[filterCols]
  filtered <- filtered[,filterCols]
  
  filtered.genes<-setdiff(rownames(all),rownames(filtered))

  write.table(filtered.genes,file=paste(output_path,study_type, paste0("filtered_genes_",study_type,".txt"), sep="/"), sep="\t",col.names='NA')

##################################################

x<-as.factor(sapply(strsplit(colnames(filtered),split="_"),"[",3))

## coefficient of Variation
co.var <- function(x) ( 100*apply(x,1,sd)/rowMeans(x) ) 

## coefficient of variation across all the sammples
cov.allGenes<-na.omit(co.var(as.matrix(filtered)))
# Using threshold (1% qauntile) for identification of non vriable genes that has least cov.


## identyfing number of genes changed acros several cov thresholds range
cov.range<-seq(range(cov.allGenes)[1], range(cov.allGenes)[2], by = 10)
ngenes<-matrix()
for (i in seq_along(cov.range)){
  ngenes[i]<- sum((cov.allGenes<=cov.range[i])*1)
}

# Using threshold (1% qauntile) for identification of non vriable genes that has least cov.
leastVar.genes<-rownames(as.matrix(sort(cov.allGenes[cov.allGenes < quantile(cov.range, c(QUANTILE_THRESHOLD))[[1]]])))
cat("leastVar genes - ", length(leastVar.genes),"\n\n")

##stVar.genes plot coefficent of variation against number of genes used to set for negative controls; i.e. genes can assumed not be influened 
## by the set of covariate of interest. 
png(file = paste(output_path,study_type, paste0("covRange_threshold.",study_type,".png") ,sep="/"), width = 750, height = 750, res=120);
plot(cov.range,ngenes, xlab="Coefficient of Variation",type="b", ylab="Number of genes",pch=16,col="blue",main="")
abline(v=quantile(cov.range, c(QUANTILE_THRESHOLD))[[1]], lwd=1, col="red")
legend("bottomright",c(QUANTILE_THRESHOLD*100,"% quantile"),lty=1, lwd=1, col="red")
dev.off()

set <- newSeqExpressionSet(as.matrix(filtered), phenoData = data.frame(x, row.names=colnames(filtered)))

##############
colors.order<-colorOrder(x)

colors <- brewer.pal(8, "Set2")
pdf(paste(output_path,study_type, paste0("unnormalised_all_", study_type,".pdf"), sep="/"), width=18, height=18)
plotRLE(set, outline=FALSE, ylim=c(-4, 4), col=colors.order)
plotPCA(set, col=colors.order, cex=0.7)
dev.off()

## upper quartile normalisation
set <- betweenLaneNormalization(set, which="upper")
pdf(paste(output_path,study_type, paste0("upperQnormalisation_",study_type,".pdf"), sep="/"), width=18, height=18)
plotRLE(set, outline=FALSE, ylim=c(-4, 4), col=colors.order)
abline(h=c(2,-2),lty=2, col="blue",lwd=2)
plotPCA(set, col=colors.order, cex=0.7)
dev.off()

#####i
cat("RUV normalisation..... \n\n")
set.RUVg <- RUVg(set, leastVar.genes[1:LEASTVARGENES_THRESHOLD] , k=1)
save(set.RUVg,file=paste(output_path,study_type,paste0("set.RUVg_",study_type, ".Rdata") ,sep="/"))
pdf(paste(output_path,study_type,paste0("RUVg_",LEASTVARGENES_THRESHOLD,"_",study_type,".pdf"), sep="/"), width=18, height=18)
plotRLE(set.RUVg, outline=FALSE, ylim=c(-4, 4), col=colors.order)
abline(h=c(2,-2),lty=2, col="blue",lwd=2)
plotPCA(set.RUVg, col=colors.order, cex=0.7)
dev.off()

## normalised expression heatmap
cat("normCounts dim", dim(normCounts(set.RUVg)))
agg_matrix_norm<-summary_tissues(normCounts(set.RUVg))
plot_heatmap(agg_matrix_norm, name=paste0("Normalised_",study_type))

# raw expression heatmap
cat("Counts dim", dim(counts(set.RUVg)))
agg_matrix_raw<-summary_tissues(counts(set.RUVg))
plot_heatmap(agg_matrix_raw, name=paste0("Raw_",study_type))

