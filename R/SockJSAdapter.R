#
# SockJSAdapter.R
#
# Copyright (C) 2009-13 by RStudio, Inc.
#
# This program is licensed to you under the terms of version 3 of the
# GNU Affero General Public License. This program is distributed WITHOUT
# ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING THOSE OF NON-INFRINGEMENT,
# MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. Please refer to the
# AGPL (http://www.gnu.org/licenses/agpl-3.0.txt) for more details.
#

local({
  # Read config directives from stdin and put them in the environment.
  fd = file('stdin')
  input <- readLines(fd)
  Sys.setenv(
  SHINY_APP=input[1],
  SHINY_PORT=input[2],
  SHINY_GAID=input[3],
  SHINY_SHARED_SECRET=input[4],
  SHINY_SERVER_VERSION=input[5],
  WORKER_ID=input[6],
  SHINY_MODE=input[7])
  close(fd)

  MIN_R_VERSION <- "2.15.1"
  MIN_SHINY_VERSION <- "0.7.0"
  MIN_RMARKDOWN_VERSION <- "0.1.90"
  MIN_KNITR_VERSION <- "1.5.32"

  # We can have a more stringent requirement for the Shiny version when using
  # rmarkdown
  MIN_SHINY_RMARKDOWN_VERSION <- "0.9.1.9005"

  options(shiny.sharedSecret = Sys.getenv('SHINY_SHARED_SECRET'))

  rVer <- as.character(getRversion());
  shinyVer <- tryCatch({as.character(packageVersion("shiny"))},
      error=function(e){"0.0.0"});
  cat(paste("R version: ", rVer, "\n", sep=""))
  cat(paste("Shiny version: ", shinyVer, "\n", sep=""))

  markdownVer <- tryCatch({as.character(packageVersion("rmarkdown"))},
      error=function(e){"0.0.0"});
  cat(paste("rmarkdown version: ", markdownVer, "\n", sep=""))

  knitrVer <- tryCatch({as.character(packageVersion("knitr"))},
      error=function(e){"0.0.0"});
  cat(paste("knitr version: ", knitrVer, "\n", sep=""))

  if (compareVersion(MIN_R_VERSION,rVer)>0){
    # R is out of date
    stop(paste("R version '", rVer, "' found. Shiny Server requires at least '",
        MIN_R_VERSION, "'."), sep="")
  }
  if (compareVersion(MIN_SHINY_VERSION,shinyVer)>0){
    if (shinyVer == "0.0.0"){
      # Shiny not found
      stop(paste("The Shiny package was not found in the library. Ensure that ",
        "Shiny is installed and is available in the Library of the ",
        "user you're running this application as.", sep="\n"))
    } else{
      # Shiny is out of date
      stop(paste("Shiny version '", shinyVer, "' found. Shiny Server requires at least '",
          MIN_SHINY_VERSION, "'."), sep="")      
    }  
  }

  mode <- Sys.getenv('SHINY_MODE')
  # Trying to use rmd, verify package.
  if (identical(mode, "rmd")){
    if (compareVersion(MIN_RMARKDOWN_VERSION,markdownVer)>0){
      if (markdownVer == "0.0.0"){
        # rmarkdown not found
        stop(paste("You are attempting to load an rmarkdown file, but the ",
          "rmarkdown package was not found in the library. Ensure that ",
          "rmarkdown is installed and is available in the Library of the ",
          "user you're running this application as.", sep="\n"))
      } else{
        # rmarkdown is out of date
        stop(paste("rmarkdown version '", markdownVer, "' found. Shiny Server requires at least '",
            MIN_RMARKDOWN_VERSION, "'."), sep="")
      } 
    }
    if (compareVersion(MIN_SHINY_RMARKDOWN_VERSION,shinyVer)>0){
      # We know it's installed b/c we got to this code chunk, so it's outdated.
      stop(paste("Shiny version '", shinyVer, "' found. Shiny Server requires at least '",
          MIN_SHINY_RMARKDOWN_VERSION, "' to use with the rmarkdown package."), sep="")
    }
    if (compareVersion(MIN_KNITR_VERSION,knitrVer)>0){
      # We know it's installed b/c we got to this code chunk, so it's outdated.
      stop(paste("knitr version '", knitrVer, "' found. Shiny Server requires at least '",
          MIN_KNITR_VERSION, "' to use with the rmarkdown package."), sep="")
    }
  }

  library(shiny)

   gaTrackingCode <- ''
   if (nzchar(Sys.getenv('SHINY_GAID'))) {
      gaTrackingCode <- HTML(sprintf("<script type=\"text/javascript\">

  var _gaq = _gaq || [];
  _gaq.push(['_setAccount', '%s']);
  _gaq.push(['_trackPageview']);

  (function() {
    var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
    ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
    var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
  })();

</script>", Sys.getenv('SHINY_GAID')))
   }

   inject <- paste(
      tags$script(src='__assets__/sockjs-0.3.min.js'),
      tags$script(src='__assets__/shiny-server.js'),
      gaTrackingCode,
      HTML("</head>"),
      sep="\n"
   )
                            
   filter <- function(...) {
      # The signature of filter functions changed between Shiny 0.4.0 and
      # 0.4.1; previously the parameters were (ws, headers, response) and
      # after they became (request, response). To work with both types, we
      # just grab the last argument.
      response <- list(...)[[length(list(...))]]

      if (response$status < 200 || response$status > 300) return(response)

      # Don't break responses that use httpuv's file-based bodies.
      if ('file' %in% names(response$content))
         return(response)
                                                
      if (!grepl("^text/html\\b", response$content_type, perl=T))
         return(response)

      # HTML files served from static handler are raw. Convert to char so we
      # can inject our head content.
      if (is.raw(response$content))
         response$content <- rawToChar(response$content)

      response$content <- sub("</head>", inject, response$content, 
         ignore.case=T)
      return(response)
   }
   options(shiny.http.response.filter=filter)
})

# Port can be either a TCP port number, in which case we need to cast to
# integer; or else a Unix domain socket path, in which case we need to
# leave it as a string
port <- suppressWarnings(as.integer(Sys.getenv('SHINY_PORT')))
if (is.na(port)) {
  port <- Sys.getenv('SHINY_PORT')
  attr(port, 'mask') <- strtoi('0077', 8)
}
cat(paste("\nStarting Shiny with process ID: '",Sys.getpid(),"'\n", sep=""))

if (identical(Sys.getenv('SHINY_MODE'), "shiny")){
  runApp(Sys.getenv('SHINY_APP'),port=port,launch.browser=FALSE)
} else if (identical(Sys.getenv('SHINY_MODE'), "rmd")){
  library(rmarkdown)
  rmarkdown::run(file=NULL, dir=Sys.getenv('SHINY_APP'),
    shiny_args=list(port=port,launch.browser=FALSE), auto_reload=FALSE)
} else{
  stop(paste("Unclear Shiny mode:", Sys.getenv('SHINY_MODE')))
}
