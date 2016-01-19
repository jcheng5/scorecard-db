Turn [College Scorecard data](https://collegescorecard.ed.gov/data/) into SQLite database.

Requires make, R (written on 3.2.3), and wget. Currently only works on OS X due to `sed` issues.

License: GPL-3

### Instructions

In the repo directory, run `make download`, then `make`. The output will be put in `output/CollegeScorecard.sqlite`.
