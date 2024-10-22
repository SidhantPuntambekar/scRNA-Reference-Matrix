library(dplyr)
library(Seurat)
library(patchwork)
library(clustifyr)
library(tidyverse)
library(digest)

D0_FACSatlas <- read_tsv("ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE143nnn/GSE143435/suppl/GSE143435_DeMicheli_D0_FACSatlas_normalizeddata.txt.gz")
D0_FACSatlas <- D0_FACSatlas %>%
  #as.data.frame() %>%
  column_to_rownames('X1')
  #as.matrix() %>%
  #t()
D0_FACSatlas[1:5, 1:5]

D0_FACSatlasMetadata <- read_tsv("ftp://ftp.ncbi.nlm.nih.gov/geo/series/GSE143nnn/GSE143435/suppl/GSE143435_DeMicheli_D0_FACSatlas_metadata.txt.gz")
D0_FACSatlasMetadata
sum(colnames(D0_FACSatlas) %in% D0_FACSatlasMetadata$X1)
ncol(D0_FACSatlas)

source("~/Reference-Matrix-Generation/R/utils/utils.r")
checkRawCounts(as.matrix(D0_FACSatlas))

GSE143435_D0Normalized <- NormalizeData(D0_FACSatlas)
GSE143435_D0Normalized

#Reference matrix build
new_ref_matrix <- average_clusters(mat = GSE143435_D0Normalized, metadata = D0_FACSatlasMetadata$cell_annotation, if_log = TRUE) #Using clustifyr seurat_ref function
new_ref_matrix_hashed <- average_clusters(mat = D0_FACSatlas, metadata = D0_FACSatlasMetadata$cell_annotation, if_log = TRUE)
head(new_ref_matrix)
tail(new_ref_matrix)
newcols <- sapply(colnames(new_ref_matrix_hashed), digest, algo = "sha1")
colnames(new_ref_matrix_hashed) <- newcols
head(new_ref_matrix_hashed)
tail(new_ref_matrix_hashed)
saveRDS(new_ref_matrix_hashed, "GSE143435D0Hashed.rds")
saveRDS(new_ref_matrix, "GSE143435D0.rds")

#Seurat analysis
#Preprocessing workflow
D0_FACS <- CreateSeuratObject(counts = D0_FACSatlas %>% t(), project = "MouseAtlas", min.cells = 3, min.features = 200)
D0_FACS
D0_FACS@assays$RNA@data <- D0_FACS@assays$RNA@counts
D0_FACS[["percent.mt"]] <- D0_FACSatlasMetadata$percent_mito
head(D0_FACS@meta.data, 5)
VlnPlot(D0_FACS, features = c("nFeature_RNA", "nCount_RNA", "percent.mt"), ncol = 3)
plot1 <- FeatureScatter(D0_FACS, feature1 = "nCount_RNA", feature2 = "percent.mt")
plot2 <- FeatureScatter(D0_FACS, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")
plot1 + plot2
D0_FACS <- subset(D0_FACS, subset = nFeature_RNA > 200 & nFeature_RNA < 2500 & percent.mt < 5)

#Variable Features
D0_FACS <- FindVariableFeatures(D0_FACS, selection.method = "vst", nfeatures = 2000)
top10 <- head(VariableFeatures(D0_FACS), 10)
plot1 <- VariableFeaturePlot(D0_FACS)
plot2 <- LabelPoints(plot = plot1, points = top10, repel = TRUE)
plot1 + plot2

#Linear dimension reduction
all.genes <- rownames(D0_FACS)
D0_FACS <- ScaleData(D0_FACS, features = all.genes)
D0_FACS <- RunPCA(D0_FACS, features = VariableFeatures(object = D0_FACS))
print(D0_FACS[["pca"]], dims = 1:5, nfeatures = 5)
VizDimLoadings(D0_FACS, dims = 1:2, reduction = "pca")
DimPlot(D0_FACS, reduction = "pca")
DimHeatmap(D0_FACS, dims = 1, cells = 500, balanced = TRUE)
DimHeatmap(D0_FACS, dims = 1:15, cells = 500, balanced = TRUE)

#Dimensionality
#D0_FACS <- JackStraw(D0_FACS, num.replicate = 1:10)
#D0_FACS <- ScoreJackStraw(D0_FACS, dims = 1:20)
#JackStrawPlot(D0_FACS, dims = 1:15)
ElbowPlot(D0_FACS)

#Cluster cells
D0_FACS <- FindNeighbors(D0_FACS, dims = 1:10)
D0_FACS <- FindClusters(D0_FACS, resolution = 0.5)
head(Idents(D0_FACS), 5)

#Non-linear dimensional reduction (UMAP/tSNE)
D0_FACS <- RunUMAP(D0_FACS, dims = 1:10)
DimPlot(D0_FACS, reduction = "umap")

#Cluster for cell marking
cluster1.markers <- FindMarkers(D0_FACS, ident.1 = 1, min.pct = 0.25)
head(cluster1.markers, n = 5)
cluster5.markers <- FindMarkers(D0_FACS, ident.1 = 5, ident.2 = 0, min.pct = 0.25)
head(cluster5.markers, n = 5)
D0_FACS.markers <- FindAllMarkers(D0_FACS.markers, only.pos = TRUE, min.pct = 0.25, logfc.threshold = 0.25)
D0_FACS.markers %>% group_by(cluster) %>% top_n(n = 2, wt = avg_logFC)
cluster1.markers <- FindMarkers(D0_FACS, ident.1 = 0, logfc.threshold = 0.25, test.use = "roc", only.pos = TRUE)

#Assigning cell types to identity to clusters
# get shared cell ids
shared_cell_ids <- intersect(rownames(D0_FACS@meta.data), D0_FACSatlasMetadata$X1)
# subset metadata
D0_FACSatlasMetadata <- filter(D0_FACSatlasMetadata, X1 %in% shared_cell_ids)
# reorder metadata
reorder_idx <- match(rownames(D0_FACS@meta.data), D0_FACSatlasMetadata$X1)
D0_FACSatlasMetadata <- D0_FACSatlasMetadata[reorder_idx, ]
# verify reordering
all(rownames(D0_FACS@meta.data) == D0_FACSatlasMetadata$X1)
# add major_cell_lineage vector to meta.data
D0_FACS@meta.data$annotated <- D0_FACSatlasMetadata$cell_annotation
head(D0_FACS@meta.data$annotated)
new.cluster.ids <- D0_FACS@meta.data$annotated
Idents(D0_FACS) <- "annotated"

#Annotated UMAP
DimPlot(D0_FACS, reduction = "umap", label = TRUE, pt.size = 0.5) + NoLegend()
head(Idents(D0_FACS), 5)

#Reference matrix build
new_ref_matrix <- average_clusters(mat = D0_FACSatlas, metadata = D0_FACS@meta.data$annotated, if_log = TRUE) #Using clustifyr seurat_ref function
new_ref_matrix_hashed <- average_clusters(mat = D0_FACSatlas, metadata = D0_FACS@meta.data$annotated, if_log = TRUE)
head(new_ref_matrix)
tail(new_ref_matrix)
newcols <- sapply(colnames(new_ref_matrix_hashed), digest, algo = "sha1")
colnames(new_ref_matrix_hashed) <- newcols
head(new_ref_matrix_hashed)
tail(new_ref_matrix_hashed)
saveRDS(new_ref_matrix_hashed, "GSE143435D0Hashed.rds")
saveRDS(new_ref_matrix, "GSE143435D0.rds")
