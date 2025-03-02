# Reference: https://github.com/carlos-alberto-silva/rGEDI

gedi_finder <- function(product, bbox) {
  
  #Reference: https://git.earthdata.nasa.gov/projects/LPDUR/repos/gedi-finder-tutorial-r/browse/GEDI_Finder.R
  
  #Define the base CMR granule search url, including LPDAAC provider name and max page size (2000 is the max allowed)
  cmr <- "https://cmr.earthdata.nasa.gov/search/granules.json?pretty=true&provider=LPDAAC_ECS&page_size=2000&concept_id="
  
  #Set up dictionary where key is GEDI shortname + version and value is CMR Concept ID
  concept_ids <- list('GEDI01_B.002'='C1908344278-LPDAAC_ECS', 
                      'GEDI02_A.002'='C1908348134-LPDAAC_ECS', 
                      'GEDI02_B.002'='C1908350066-LPDAAC_ECS')
  
  #CMR uses pagination for queries with more features returned than the page size
  page <- 1
  bbox <- sub(' ', '', bbox)  # Remove any white spaces
  granules <- list()          # Set up a list to store and append granule links to
  
  #Send GET request to CMR granule search endpoint w/ product concept ID, bbox & page number
  cmr_response <- GET(sprintf("%s%s&bounding_box=%s&pageNum=%s", cmr, concept_ids[[product]],bbox,page))
  
  #Verify the request submission was successful
  if (cmr_response$status_code==200){
    
    # Send GET request to CMR granule search endpoint w/ product concept ID, bbox & page number, format return as a list
    cmr_response <- content(GET(sprintf("%s%s&bounding_box=%s&pageNum=%s", cmr, concept_ids[[product]],bbox,page)))$feed$entry
    
    # If 2000 features are returned, move to the next page and submit another request, and append to the response
    while(length(cmr_response) %% 2000 == 0 && length(cmr_response) != 0){
      page <- page + 1
      cmr_response <- c(cmr_response, content(GET(sprintf("%s%s&bounding_box=%s&pageNum=%s", cmr, concept_ids[[product]],bbox,page)))$feed$entry)
    }
    
    # CMR returns more info than just the Data Pool links, below use for loop to go through each feature, grab DP link, and add to list
    for (i in 1:length(cmr_response)) {
      granules[[i]] <- cmr_response[[i]]$links[[1]]$href
    }
    
    # Return the list of links
    return(granules)
  } else {
    
    # If the request did not complete successfully, print out the response from CMR
    print(content(GET(sprintf("%s%s&bounding_box=%s&pageNum=%s", cmr, concept_ids[[product]],bbox,page)))$errors)
  }
}

gedi_finder_temp_filter <- function(roi_name, product, bbox, daterange, download_path){
  
  # Call the gedi_finder function using the user-provided inputs
  granules <- gedi_finder(product, bbox)
  
  # Temporally filter using date range
  #defining start and end dates
  start_date <- daterange[1]
  end_date <- daterange[2]
  
  #formatting dates from granules list
  found_orbits <- data.frame(url = grep('.h5$', unlist(granules), value = TRUE), stringsAsFactors = FALSE)
  found_orbits$yyyydoy <- substr(start = 0, stop = 7, x = gsub('^.+_B_|_02_005_0.+.h5$', '', found_orbits$url))
  found_orbits$yyyymmdd <- as.Date(sapply(found_orbits$yyyydoy, function(x){
    as.character(as.Date(x = as.numeric(substr(x, start = 5, stop = 7)),
                         origin = paste0(substr(x, start = 0, stop = 4), "-01-01")))
  }))
  
  #filtering to orbits within date range
  found_orbits <- found_orbits[found_orbits$yyyymmdd >= as.Date(daterange[1]) & found_orbits$yyyymmdd <= as.Date(daterange[2]), ]
  orbit_list <- found_orbits$url
  print(sprintf("%s %s Version 2 granules found.", length(orbit_list), product))
  
  # Export Results
  # Set up output textfile name
  outName <- sprintf("%s_%s.txt", roi_name, sub('.002', '_002', product))
  outDir <- paste0(download_path, 'textfiles/')
  dir.create(outDir, recursive = TRUE, showWarnings = FALSE)
  
  # Save to text file in current working directory
  filepath <- paste0(outDir, outName)
  write.table(orbit_list, filepath, row.names = FALSE, col.names = FALSE, quote = FALSE, sep='\n')
  print(sprintf("File containing links to intersecting %s Version 2 data has been saved to: %s", product, filepath))
  
  return(filepath)
  
}

gedifinder<-function(product, ul_lat, ul_lon, lr_lat, lr_lon,version="001",daterange=NULL){
  response = curl::curl(sprintf(
    "https://lpdaacsvc.cr.usgs.gov/services/gedifinder?%s=%s&%s=%s&%s=%f,%f,%f,%f&output=json",
    "version",version,
    "product", product,
    "bbox", ul_lat, ul_lon, lr_lat,lr_lon))
  content = suppressWarnings(readLines(response))
  close(response)
  results = jsonlite::parse_json(content)
  if(results$message != "") {
    stop(results$message)
  }
  
  out<-simplify2array(results$data)
  
  if (!is.null(daterange)){
    dates<-as.Date(gsub(".*(\\d{4})\\.(\\d{2})\\.(\\d{2}).*", "\\1-\\2-\\3",out))
    out_sub<-out[dates >= as.Date(daterange[1]) & dates <= as.Date(daterange[2])]
    
    if(length(out_sub)<1) {
      stop(paste("There are not GEDI data avalaible between",daterange[1],"and",daterange[2]))
    } else {
      return(out_sub)
    }
  } else {
    return(out)
  }
}

gediDownload<-function(filepath, outdir = NULL, overwrite = FALSE, buffer_size = 512, timeout=10){
  if (is.null(outdir)) {
    outdir == tempdir()
  }
  stopifnotMessage(
    "outdir is not a valid path" = checkParentDir(outdir),
    "overwrite is not logical" = checkLogical(overwrite),
    "buffer_size is not an integer" = checkInteger(buffer_size)
  )
  buffer_size = as.integer(buffer_size)
  netrc = getNetRC(outdir)
  
  files<-filepath
  n_files = length(files)
  
  # Download all files in filepath vector
  for (i in 1:n_files) {
    url = files[i]
    message("------------------------------")
    message(sprintf("Downloading file %d/%d: %s", i, n_files, basename(url)))
    message("------------------------------")
    
    if (gediDownloadFile(
      url,
      outdir,
      overwrite,
      buffer_size,
      netrc,
      timeout
    ) == 0) {
      message("Finished successfully!")
    } else {
      stop(sprintf("File %s has not been downloaded properly!", basename(url)))
    }
  }
}

gediDownloadFile = function(url, outdir, overwrite, buffer_size, netrc, timeout) {
  filename <- file.path(outdir, basename(url)) # Keep original filename
  if((! overwrite) && file.exists(filename)) {
    message("Skipping this file, already downloaded!")
    return(0)
  } # Skip if already downloaded
  
  # Temporary to file to resume to
  resume=paste0(filename, ".curltmp")
  if(file.exists(resume)){
    resume_from=file.info(resume)$size # Get current size to resume from
  } else {
    resume_from=0
  }
  
  # Connection config
  h = curl::new_handle()
  curl::handle_setopt(h, netrc=1, netrc_file=netrc, resume_from=resume_from, connecttimeout=timeout)
  
  tryCatch({
    fileHandle=file(resume, open="ab", raw = T)
    message("Connecting...")
    conn = tryCatch(curl::curl(url, handle=h, open="rb"), error = function(e) {
      file.remove(netrc)
      stop(e)
    })
    message("Connected successfully, downloading...")
    headers=rawToChar(curl::handle_data(h)$headers)
    total_size=as.numeric(gsub("[^\u00e7]*Content-Length: ([0-9]+)[^\u00e7]*","\\1",x=headers, perl = T))
    while(TRUE) {
      message(sprintf("\rDownloading... %.2f/%.2fMB (%.2f%%)    ",
                      resume_from/1024.0/1024.0,
                      total_size/1024.0/1024.0,
                      100.0*resume_from/total_size),
              appendLF=FALSE)
      data = readBin(conn, what = raw(), n = 1024*buffer_size)
      size = length(data)
      if (size==0) {
        break
      }
      writeBin(data, fileHandle, useBytes = T)
      resume_from = resume_from + size
    }
    message(sprintf("\rDownloading... %.2f/%.2fMB (100%%)    ",
                    total_size/1024.0/1024.0,
                    total_size/1024.0/1024.0))
    close(fileHandle)
    close(conn)
    file.rename(resume, filename)
    return(0)
  }, interrupt=function(e){
    warning("\nDownload interrupted!!!")
    try(close(conn), silent = TRUE)
    try(close(fileHandle), silent = TRUE)
  }, finally = {
    try(close(conn), silent = TRUE)
    try(close(fileHandle), silent = TRUE)
  })
  return(-1)
}

getNetRC = function(dl_dir) {
  netrc <- file.path(dl_dir,'.netrc')  # Path to netrc file
  # ------------------------------------CREATE .NETRC FILE------------------------------------------ #
  if (file.exists(netrc) == FALSE || any(grepl("urs.earthdata.nasa.gov", readLines(netrc))) == FALSE) {
    netrc_conn <- file(netrc)
    
    # User will be prompted for NASA Earthdata Login Username and Password below
    writeLines(c("machine urs.earthdata.nasa.gov",
                 sprintf("login %s", getPass::getPass(msg = "Enter NASA Earthdata Login Username \n (or create an account at urs.earthdata.nasa.gov) :")),
                 sprintf("password %s", getPass::getPass(msg = "Enter NASA Earthdata Login Password:"))), netrc_conn)
    close(netrc_conn)
    message("A .netrc file with your Earthdata Login credentials was stored in the output directory ")
  }
  return (netrc)
}

readLevel1B <-function(level1Bpath) {
  level1b_h5 <- hdf5r::H5File$new(level1Bpath, mode = 'r')
  level1b<- new("gedi.level1b", h5 = level1b_h5)
  return(level1b)
}

readLevel2A <-function(level2Apath) {
  level2a_h5 <- hdf5r::H5File$new(level2Apath, mode = 'r')
  level2a<- new("gedi.level2a", h5 = level2a_h5)
  return(level2a)
}

readLevel2B <-function(level2Bpath) {
  level2b_h5 <- hdf5r::H5File$new(level2Bpath, mode = 'r')
  level2b<-new("gedi.level2b", h5 = level2b_h5)
  return(level2b)
}

getLevel1BGeo<-function(level1b,select=c("elevation_bin0", "elevation_lastbin")) {
  
  select<-unique(c("latitude_bin0", "latitude_lastbin", "longitude_bin0", "longitude_lastbin","shot_number",select))
  level1b<-level1b@h5
  
  datasets<-hdf5r::list.datasets(level1b, recursive = T)
  datasets_names<-basename(datasets)
  
  selected<-datasets_names %in% select
  
  for ( i in select){
    if  ( i =="shot_number"){
      assign(i,bit64::as.integer64(NaN))
    } else {
      assign(i,numeric())
    }
  }
  
  dtse2<-datasets[selected][!grepl("geolocation/shot_number",datasets[selected])]
  
  
  # Set progress bar
  pb <- utils::txtProgressBar(min = 0, max = length(dtse2), style = 3)
  i.s=0
  
  for ( i in dtse2){
    i.s<-i.s+1
    utils::setTxtProgressBar(pb, i.s)
    name_i<-basename(i)
    if ( name_i =="shot_number"){
      assign(name_i, bit64::c.integer64(get(name_i),level1b[[i]][]))
    } else {
      assign(name_i, c(get(name_i), level1b[[i]][]))
    }
  }
  
  level1b.dt<-data.table::data.table(as.data.frame(get("shot_number")[-1]))
  select2<-select[!select[]=="shot_number"]
  
  for ( i in select2){
    level1b.dt[,i]<-get(i)
  }
  
  colnames(level1b.dt)<-c("shot_number",select2)
  close(pb)
  return(level1b.dt)
}

getLevel1BWF<-function(level1b,shot_number){
  
  level1b<-level1b@h5
  groups_id<-grep("BEAM\\d{4}$",gsub("/","",
                                     hdf5r::list.groups(level1b, recursive = F)), value = T)
  
  i=NULL
  for ( k in groups_id){
    gid<-max(level1b[[paste0(k,"/shot_number")]][]==shot_number)
    if (gid==1) {i=k}
  }
  
  if(is.null(i)) {
    stop(paste0("Shot number ", shot_number, " was not found within the dataset!. Please try another shot number"))
  } else{
    
    shot_number_i<-level1b[[paste0(i,"/shot_number")]][]
    shot_number_id<-which(shot_number_i[]==shot_number)
    elevation_bin0<-level1b[[paste0(i,"/geolocation/elevation_bin0")]][]
    elevation_lastbin<-level1b[[paste0(i,"/geolocation/elevation_lastbin")]][]
    rx_sample_count<-level1b[[paste0(i,"/rx_sample_count")]][]
    rx_sample_start_index<-level1b[[paste0(i,"/rx_sample_start_index")]][]
    rx_sample_start_index_n<-rx_sample_start_index-min(rx_sample_start_index)+1
    rxwaveform_i<-level1b[[paste0(i,"/rxwaveform")]][rx_sample_start_index_n[shot_number_id]:(rx_sample_start_index_n[shot_number_id]+rx_sample_count[shot_number_id]-1)]
    rxwaveform_inorm<-(rxwaveform_i-min(rxwaveform_i))/(max(rxwaveform_i)-min(rxwaveform_i))*100
    elevation_bin0_i<-elevation_bin0[shot_number_id]
    elevation_lastbin_i<-elevation_lastbin[shot_number_id]
    z=rev(seq(elevation_lastbin_i,elevation_bin0_i,(elevation_bin0_i-elevation_lastbin_i)/rx_sample_count[shot_number_id]))[-1]
    
    waveform<-new("gedi.fullwaveform", dt = data.table::data.table(rxwaveform=rxwaveform_i,elevation=z))
    
    return(waveform)
  }
}

stopifnotMessage = function(...) {
  ok = TRUE
  errors = list()
  listargs = list(...)
  for (i in 1:length(listargs)) {
    if (listargs[i] == FALSE) {
      errors[[""]] = names(listargs)[i]
      ok = FALSE
    }
  }
  if (ok == FALSE) {
    stop(paste0("\n\nWhen validating the arguments:\n    ", paste(errors, collapse="\n    ")))
  }
}

checkNumericLength = function(x, len) {
  return (is.null(x) || (length(x) == len && is.numeric(x)))
}

checkNumeric = function(x) {
  return (checkNumericLength(x, 1))
}

checkLogical = function(x) {
  return (is.null(x) || (length(x) == 1 && is.logical(x)))
}

checkInteger = function(x) {
  x_int = as.integer(x)
  return (is.null(x) || (length(x_int) == 1 && is.integer(x_int) && !is.na(x_int)))
}

checkCharacter = function(x) {
  return (is.null(x) || (length(x) == 1 && is.character(x)))
}

checkFilepath = function(x, newFile=TRUE, optional = TRUE) {
  exists = TRUE
  if (is.null(x)) {
    if (optional)
      return (TRUE)
    else
      return (FALSE)
  }
  if (!is.character(x) || length(x) != 1)
    return (FALSE)
  
  
  if (!newFile)
    return (file.exists(x))
  
  return (TRUE)
}

checkParentDir = function(x, optional=FALSE) {
  if (optional && is.null(x)) {
    return (TRUE)
  }
  dirName = fs::path_dir(x)
  return (fs::dir_exists(dirName)[[1]])
}

inputOrInList = function(input) {
  inList=NULL
  if (length(input) > 1) {
    inList = tempfile(fileext=".txt")
    fileHandle = file(inList, "w")
    writeLines(input, fileHandle)
    close(fileHandle)
    return (list(NULL, inList))
  }
  return (list(input, NULL))
}

cleanInList = function(x) {
  if (!is.null(x[[2]]) && file.exists(x[[2]])) {
    file.remove(x[[2]])
  }
}
