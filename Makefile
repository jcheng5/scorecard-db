DATADIR= ./CollegeScorecard_Raw_Data

INFILES := $(sort $(wildcard $(DATADIR)/MERGED*.csv))
OUTFILES := $(subst $(DATADIR),working,$(INFILES))

all : output/CollegeScorecard.sqlite

CollegeScorecard_Raw_Data.zip :
	wget https://s3.amazonaws.com/ed-college-choice-public/CollegeScorecard_Raw_Data.zip

$(DATADIR)/MERGED1996_PP.csv : CollegeScorecard_Raw_Data.zip
	unzip CollegeScorecard_Raw_Data.zip
	touch $@

working/00header.csv : $(DATADIR)/MERGED1996_PP.csv
	mkdir -p working
	printf YEAR, > "$@"
	# Just grab the first line, and strip off the byte order mark (BOM)
	head -n1 <"$<" | sed '1 s/^\xef\xbb\xbf//' >>"$@"

working/MERGED%_PP.csv : $(DATADIR)/MERGED%_PP.csv
	# Skip the header, strip NULL and PrivacySuppressed, and prepend year column
	tail -n+2 "$<" | sed "s/NULL\|PrivacySuppressed//g" | sed "s/^/$*,/" > "$@"

clean :
	rm -f working/*
	rm -f output/*

purge : clean
	rm -rf CollegeScorecard_Raw_Data CollegeScorecard_Raw_Data.zip

output/merged.csv : working/00header.csv $(OUTFILES)
	# Just cat together all cleaned CSVs, including header
	mkdir -p output
	cat working/*.csv > output/merged.csv

bootstrap_r :
	# Ensure packrat has been bootstrapped
	R --vanilla --slave -f packrat/init.R --args --bootstrap-packrat

output/CollegeScorecard.sqlite : output/merged.csv bootstrap_r
	rm -f $@
	Rscript normalize_data.R

# add leading zeroes to floats
# sed 's/,\.\([0-9]\+\)/,0.\1/g'