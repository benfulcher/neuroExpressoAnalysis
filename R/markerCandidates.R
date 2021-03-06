#' Write candidate marker genes to a file
#' 
#' Writes candidate marker genes to a file along with other required information (fold change and silhouette coefficient)
#' Selects candidates based on fold change to the median expression of other samples and a minimum expression in the
#' cell type
#' 
#' @param design data.frame. Metadata for the samples.
#' @param expression data.frame. Expression data for the samples. Gene names should be included as a column. Any other non expression
#' data not be of type \code{double}
#' @param outLoc Directory to save the candidate genes
#' @param groupNames column of the \code{design} with cell type names. If multiple columns are provided, selection will
#' be performed for each independently
#' @param regionNames column of the \code{design} with region names. Multiple regions can be listed separated by commas
#' @param PMID column of the \code{design} with pubmed identifiers. This is required to identify the samples coming
#' from the same study
#' @param rotate double. percentage of samples to be removed. 0.33 is used for the study
#' @param cores Number of cores to use for paralellization
#' @param debug Nothing to see here
#' @param sampleName column of the \code{design} with sample names matching the column names of the \code{expression} data
#' @param replicates column of the \code{design} that groups replicates
#' @param foldChangeThresh minimum fold change required for selection
#' @param minimumExpression minimum level of expression for a marker gene in its cell type
#' @param regionHiearchy hiearchy of regions.
#' @param seed seed for random generation. if NULL will be set to random
#' @export
markerCandidates = function(design,
                      expression,
                      outLoc,
                      groupNames,
                      regionNames=NULL,
                      PMID = 'PMID',
                      rotate = NULL,
                      cores = 4,
                      debug=NULL, 
                      sampleName = 'sampleName',
                      replicates = 'originalIndex',
                      foldChangeThresh = 10,
                      minimumExpression = 8,
                      regionHierarchy = NULL,
                      geneID = 'Gene.Symbol',
                      seed = NULL){
    #browser()
    # source('R/regionHierarchy.R')
    # so that I wont fry my laptop
    if(!is.na(detectCores())){
    if (detectCores()<cores){ 
        cores = detectCores()
        print('max cores exceeded')
        print(paste('set core no to',cores))
    }
    }
    registerDoMC(cores)
    
    #gene selector, outputs selected genes and their fold changes
    foldChange = function (group1, group2, f = 10){
        
        
        groupAverage1 = group1
        
        
        
        groupAverage2 = tryCatch({apply(group2, 2, median)},
                                 error = function(cond){
                                     print('fuu')
                                     return(group2)
                                 })
        
        g19 = groupAverage1 < (log(10,base=2) + 6) & groupAverage1 > minimumExpression
        g16 = groupAverage1  < 6
        g29 = groupAverage2 < (log(10,base=2) + 6) & groupAverage2 > minimumExpression
        g26 = groupAverage2 < 6
        # this is a late addition preventing anything that is below 8 from being
        # selected. ends up removing the the differentially underexpressed stuff as well
        gMinTresh = groupAverage1 > minimumExpression
        
        
        tempGroupAv2 = vector(length = length(groupAverage2))
        
        tempGroupAv2[g26 & g19] =apply(group2[, g26 & g19,drop=F], 2, max)
        # legacy 
        tempGroupAv2[g16 & g29] =apply(group2[, g16 & g29,drop=F], 2, min)
        
        
        
        add1 = g19 & g26 & groupAverage1>tempGroupAv2
        add2 = g29 & g16 & tempGroupAv2>groupAverage1
        
        
        fold = groupAverage1 - groupAverage2
        # take everything below 6 as the same when selecting
        # fold =  sapply(groupAverage1,max,6) - sapply(groupAverage2,max,6)
        chosen =  which(({(fold >= (log(f)/log(2))) & !(g19 & g26) } | {(fold <= log(1/f)/log(2)) &  !(g29 & g16)}| add1 | add2)&gMinTresh)
        return(
            data.frame(index = chosen, foldChange = fold[chosen])
        )
    }
    
    giveSilhouette = function(daGeneIndex,groupInfo1,groupInfo2){
        clustering = as.integer(rep(1,nrow(design))*(1:nrow(design) %in% groupInfo1)+1)
        clustering = clustering[1:nrow(design) %in% c(groupInfo1, groupInfo2)]
        data = (exprData[ (1:nrow(design) %in% c(groupInfo1, groupInfo2)),  daGeneIndex])
        cluster = list(clustering = clustering, data = data)
        silo = silhouette(cluster,dist(data))
        return(mean(silo[,3]))    
    }
    # data prep. you transpose exprData -----
    #design = read.design(designLoc)
    
    #expression = read.csv(exprLoc, header = T)
    list[geneData, exprData] = sepExpr(expression)
    
    if (!all(colnames(exprData) %in% design[[sampleName]])){
        if(is.null(rotate)){
            print('Unless you are rotating samples, something has gone terribly wrong!')
        }
        exprData = exprData[,colnames(exprData) %in% design[[sampleName]]]
    }
    
    design = design[match(colnames(exprData),design[[sampleName]],),]
    
    exprData = t(exprData)
    noReg = F
    if (is.null(regionNames)){
        regionNames = 'dummy'
        design[,regionNames] = 'dummy'
        noReg = T
    }
    
    
    regionGroups = memoReg(design,regionNames,groupNames,regionHierarchy)
    # concatanate new region based groups to design and to groupNames so they'll be processed normally
    if (!noReg){
        design = cbind(design,regionGroups)
        groupNamesEn = c(groupNames, names(regionGroups))
    } else {
        groupNamesEn = groupNames
    }
    
    # generate nameGroups to loop around -----
    nameGroups = vector(mode = 'list', length = len(groupNamesEn))
    
    
    names(nameGroups) = c(groupNamesEn)
    
    for (i in 1:len(groupNamesEn)){
        nameGroups[[i]] = design[,groupNamesEn[i]]
    }
    nameGroups = nameGroups[unlist(lapply(lapply(lapply(nameGroups,unique),trimNAs),length)) > 1]
    #debug exclude
    if (!is.null(debug)){
        nameGroups = nameGroups[names(nameGroups) %in% debug]
        groupNamesEn = groupNamesEn[groupNamesEn %in% debug]
    } 
    groupNamesEn = names(nameGroups)
    
    # the main loop around groups ------
    if (!is.null(seed)){
        registerDoRNG(seed)
    } else {
        registerDoRNG()
    }
    foreach (i = 1:len(nameGroups)) %dorng% {
        #for (i in 1:len(nameGroups)){
        #debub point for groups
        typeNames = trimNAs(unique(nameGroups[[i]]))
        realGroups = vector(mode = 'list', length = length(typeNames))
        names(realGroups) = typeNames
        for (j in 1:length(typeNames)){
            realGroups[[j]] = which(nameGroups[[i]] == typeNames[j])
        }
        
        
        if (!is.null(rotate)){
            # this part equalizes representation from individual studies when rotating. 
            print('yayay')
            realGroups2 = lapply(realGroups, function(x){
                articles = design[x,PMID]
                minRepresentation = articles %>%
                    table(useNA = 'ifany') %>% 
                    min
                lapply (1:len(unique(articles)),function(j){
                    # this turned into a list because if it is not a list, single length vectors behave differently
                    # in sample. 
                    if (len( x[articles %in% unique(articles)[j]]) ==1){
                        return(x[articles %in% unique(articles)[j]])
                    }
                    x[articles %in% unique(articles)[j]] %>% 
                        sample(size=minRepresentation,replace=FALSE) %>% unlist #%>% #if you decide to remove samples per study comment this part in, delete the part below
                    #sample(.,size = len(.)-round(len(.)*rotate), replace= FALSE)        
                }) %>% unlist
            })
            removed = unlist(realGroups)[!unlist(realGroups) %in% unlist(realGroups2)]
            realGroups = realGroups2
            
            # if rotation is checked, get a subset of the samples. result is rounded. so too low numbers can make it irrelevant
            realGroups2 = lapply(realGroups,function(x){
                if(len(x)==1){
                    warning('Samples with single replicates. Bad brenna! bad!')
                    return(x)
                }
                sort(sample(x,len(x)-round(len(x)*rotate)) %>% unlist)
            })
            removed = c(removed, unlist(realGroups)[!unlist(realGroups) %in% unlist(realGroups2)])
            realGroups = realGroups2
        }
        tempExpr = exprData[unlist(realGroups),]
        tempDesign = design[unlist(realGroups),]
        
        
        
        
        # replicateMeans ------
        # inefficient if not rotating but if you are not rotating you are only doing it once anyway
        
        indexes = unique(tempDesign[[replicates]])
        
        
        
        repMeanExpr = sapply(1:len(indexes), function(j){
            tryCatch({
                apply(tempExpr[tempDesign[[replicates]] == indexes[j],], 2,mean)},
                error= function(e){
                    if (is.null(rotate)){
                        print('unless you are rotating its not nice that you have single replicate groups')
                        print('you must be ashamed!')
                        print(j)
                    }
                    tempExpr[tempDesign[[replicates]] == indexes[j],]
                })
        })
        repMeanExpr = t(repMeanExpr)
        repMeanDesign = tempDesign[match(indexes,tempDesign[[replicates]]),]
        
        # since realGroups is storing the original locations required for
        # silhouette store the new locations to be used with repMeanExpr here
        # use the old typeNames since that cannot change
        realGroupsRepMean =  vector(mode = 'list', length = length(typeNames))
        print(names(nameGroups)[i])
        for (j in 1:length(typeNames)){
            realGroupsRepMean[[j]] = which(repMeanDesign[,groupNamesEn[i]] == typeNames[j])
        }
        names(realGroupsRepMean) = typeNames
        
        # groupMeans ----
        #take average of every group
        
        groupAverages = sapply(realGroupsRepMean, function(j){
            groupAverage = apply(repMeanExpr[j,,drop=F], 2, mean)
            
        })
        groupAverages = t(groupAverages)
        
        # creation of output directories ----
       # dir.create(paste0(outLoc ,'/Marker/' , names(nameGroups)[i] , '/'), showWarnings = F,recursive = T)
       # dir.create(paste0(outLoc , '/Relax/' , names(nameGroups)[i] , '/'), showWarnings = F, recursive =T)
       dir.create(paste0(outLoc ,'/' , names(nameGroups)[i] , '/'), showWarnings = F, recursive =T)
        if (!is.null(rotate)){
            write.table(removed,
                        file = paste0(outLoc,'/',names(nameGroups)[i] , '/removed'),
                        col.names=F)
        }
        
        # for loop around groupAverages
        for (j in 1:nrow(groupAverages)){
            # cell type specific debug point
            #if (names(realGroups)[j]=='GabaOxtr'){
            #  print('loyloy')  
            #}
            fileName = paste0(outLoc ,'/', names(nameGroups)[i], '/',  names(realGroups)[j])
           # fileName2 = paste0(outLoc , '/Marker/' , names(nameGroups)[i] , '/' , names(realGroups)[j])
            
            # find markers. larger than 10 fold change to every other group
#             isMarker = apply(groupAverages,2,function(x){
#                 all(x[-j] + log(10, base=2) < x[j])
#             })  
#             
#             fMarker = data.frame(geneData$Gene.Symbol[isMarker], groupAverages[j,isMarker], apply(groupAverages[-j,isMarker,drop=F],2,max), apply(groupAverages[-j,isMarker,drop=F],2,min))
            fChange = foldChange(groupAverages[j, ], groupAverages[-j,,drop=F] ,foldChangeThresh)
            fChangePrint = data.frame(geneNames = geneData[[geneID]][fChange$index], geneFoldChange= fChange$foldChange )
            fChangePrint = fChangePrint[order(fChangePrint$geneFoldChange, decreasing=T) ,]
            
            #silhouette. selects group members based on the original data matrix
            # puts them into two clusters to calculate silhouette coefficient
            groupInfo1 = realGroups[[j]]
            groupInfo2 = unlist(realGroups[-j])
            
            silo = vector(length = nrow(fChangePrint))
            if (!nrow(fChangePrint) == 0){
                for (t in 1:nrow(fChangePrint)){
                    # gene specific debug point
                    # if(fChangePrint$geneNames[t] == 'Lmo7'){
                    #     print('gaaaaa')
                    # }
                    silo[t] = giveSilhouette(which(geneData[[geneID]] == fChangePrint$geneNames[t]),
                                             groupInfo1,
                                             groupInfo2)
                }
                fChangePrint = cbind(fChangePrint, silo)
            } else {
                fChangePrint = data.frame(fChangePrint, silo=numeric(0))
            }
            
            
            print(fileName)
            # print(nameGroups[[i]])
            write.table(fChangePrint, quote = F, row.names = F, col.names = F, fileName)
           # write.table(fMarker, quote = F, row.names = F, col.names = F, fileName2)
            
        }# end of for around groupAverages
        
    } # end of foreach loop around groups
} # end of function