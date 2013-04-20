#!/usr/bin/env R
# mindset_json.R
# R script to build dataframes from Mindset JSON
# (c) Copyright 2013 mkgs@github http://github.com/mkfs/mindset
# License: BSD http://www.freebsd.org/copyright/freebsd-license.html

library(rjson)

mindset.raw.df <- function(lst) {
	num = length(lst$wave)
	data.frame( index=1:num, raw=lst$wave )
}

mindset.wave.df <- function(lst) {
	data.frame( delta=lst$delta, theta=lst$theta, 
		    alpha.low=lst$lo_alpha, alpha.high=lst$hi_alpha,
		    beta.low=lst$lo_beta, beta.high=lst$hi_beta,
		    gamma.low=lst$lo_gamma, gamma.high=lst$mid_gamma,
		    attention=lst$attention, meditation=lst$meditation,
		    signal=lst$signal_quality )
}

mindset.from.json <- function(fname='mindset.json') {
	l_data <- fromJSON(file=fname)
	# FIXME: turn into a date
	# timestamp=as.POSIXct(l_data$start_ts),
	list( start=l_data$start_ts,
	      end=l_data$end_ts,
	      eeg=mindset.raw.df(l_data), 
	      brainwave=mindset.wave.df(l_data) )
}
