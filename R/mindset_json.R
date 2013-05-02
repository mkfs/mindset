#!/usr/bin/env R
# mindset_json.R
# R script to build dataframes from Mindset JSON
# (c) Copyright 2013 mkgs@github http://github.com/mkfs/mindset
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

library(rjson)

# Generate a dataframe for raw EEG data. This stores each datapoint as a row,
# so that the datafrmae can be used for time series analysis. To combine
# multiple dataframes (i.e. multiple same-length recordings), rename the 'raw'
# column and drop all 'index' columns except the first.
# Columns: index raw
mindset.raw.df <- function(lst) {
	num = length(lst$wave)
	# FIXME: replace index with ms count
	data.frame( index=1:num, raw=lst$wave )
}

# Generate a dataframe for Mindset brainwave data.
# Columns: delta theta alpha.low alpha.high beta.low beta.high i
#          gamma.low gamma.high attention meditation siqnal
mindset.wave.df <- function(lst) {
	data.frame( delta=lst$delta, theta=lst$theta, 
		    alpha.low=lst$lo_alpha, alpha.high=lst$hi_alpha,
		    beta.low=lst$lo_beta, beta.high=lst$hi_beta,
		    gamma.low=lst$lo_gamma, gamma.high=lst$mid_gamma,
		    attention=lst$attention, meditation=lst$meditation,
		    signal=lst$signal_quality )
}

# Generate a list with the following elements:
#   start     : timestamp at start of recording
#   end       : timestamp at start of recording
#   eeg       : dataframe of raw EEG data
#   brainwave : dataframe of Mindset brainwave (eSense, ASIC) data
# Note: this takes as input a list obtained from parsing MindSet JSON data.
mindset.from.json.list <- function(l_data) {
	# FIXME: turn into a date
	# timestamp=as.POSIXct(l_data$start_ts),
	list( start=l_data$start_ts,
	      end=l_data$end_ts,
	      eeg=mindset.raw.df(l_data), 
	      brainwave=mindset.wave.df(l_data) )
}

# Parse a JSON string and return a list (start, end, raw, brainwave).
mindset.from.json <- function(json_str) {
	mindset.from.json.list( fromJSON(json_str) )
}

# Read in a JSON file and return a list (start, end, raw, brainwave).
mindset.from.json.file <- function(fname='mindset.json') {
	mindset.from.json.list( fromJSON(file=fname) )
}
