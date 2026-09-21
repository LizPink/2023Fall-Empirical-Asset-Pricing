libname code "F:\Momentum";

* Step1 : Specifying options;
%let J = 6; * Formation period length: J can be between 3 to 12 months;
%let K = 6; * Holding   period length: K can be between 3 to 12 months;

* Jegadeesh and Titman's Footnote 4 page 69: 1965-1989 are holding period dates
* Need 2 years of return history to form mometum portfolios that start in 1965;
%let begdate=01JAN1963; 
%let enddate=31DEC1989;



* Step 2: Extract CRSP Data for NYSE and AMEX Common Stocks, Merge historical codes with CRSP Monthly Stock File
Restriction on Share Code: common shares only and Exchange Code: NYSE and AMEX securities only;
data data; set code.originaldailydata;
if shrcd in (10,11) and exchcd in (1,2);
if "01Jan1963"d <= date <= "31Dec1989"d;
yearmonth = intnx("month",date,0,'e'); format yearmonth date9.; 
prc = abs(prc);
run;

data dx; set data; keep date; run;
proc sort data = dx nodupkey; by date; run;
data dx; set dx; dx = _N_; run;

data mx; set data; keep yearmonth; run;
proc sort data = mx nodupkey; by yearmonth; run;
data mx; set mx; mx = _N_; run;

proc sort data = data; by date; run;
data data; merge data(in=ina) dx; by date; if ina; run;

proc sort data = data; by yearmonth; run;
data data; merge data(in=ina) mx; by yearmonth; if ina; run;


* Step 3: Create Momentum Port. Measures Based on Past (J) Month Compounded Returns; 
/* Make sure to keep stocks with available return info in the formation period */
proc sort data = data; by permno yearmonth date; run;
data monthdata; set data;
by permno yearmonth date;
if last.yearmonth;
keep permno yearmonth mx;
run;

proc sql;
create table monthdata 
as select distinct a.permno,a.yearmonth, a.mx, exp(sum(log(1+b.ret)))-1 as mret, count(b.ret) as ndays
from monthdata as a left join data as b
on a.permno = b.permno and a.yearmonth = b.yearmonth
group by a.permno, a.yearmonth;
quit;


%macro mom(J,K);
proc sql;
create table formationdata
as select distinct a.permno, a.yearmonth, a.mx, exp(sum(log(1+b.mret)))-1 as lmret&J., count(b.mret) as nmonths
from monthdata as a left join monthdata as b
on a.permno = b.permno and -%eval(&J-1) <= (b.mx - a.mx) <= 0
group by a.permno, a.yearmonth;
quit;


/* Formation of 10 Momentum Portfolios Every Month */
proc sort data = formationdata; by yearmonth; run;
proc rank data = formationdata out = formationdata group = 10; by yearmonth; var lmret&j.; ranks lmomr; run;
data formationdata; set formationdata;
if lmomr ne .;
run;

* Step 4. Assign Ranks to the Next 6 (K) Months After Portfolio Formation;
/* MOMR is the portfolio rank variable taking values between 1 and 10: */
/*          1 - the lowest  momentum group: Losers   */
/*         10 - the highest momentum group: Winners  */

%macro a;
%do i = 1 %to &K.;
data holdingdata&i.; set formationdata;
mx = mx + &i.;
keep permno mx lmomr;
run;
proc sql;
create table holdingdata&i.
as select a.*, b.mret as fmret
from holdingdata&i. as a left join monthdata as b
on a.permno = b.permno and a.mx = b.mx;
quit;
data holdingdata&i.; set holdingdata&i.; holding = &i.; run;
%end;
%mend;
%a;

data all; set holdingdata1-holdingdata&K.;
run;


proc sort data = all; by mx lmomr; run;
proc means data = all noprint;
by mx lmomr;
var fmret;
output out = allmean (drop=_TYPE_ _FREQ_) mean = fmret;
run;


* buy - sell;
proc sort data = allmean; by mx; run;
proc transpose data = allmean out = allmean1;
by mx;
id lmomr;
var fmret;
run;
data allmean1; set allmean1;
fmret = _9 - _0;
lmomr = 99;
keep mx fmret lmomr;
run;
data allmean; set allmean allmean1; run;


proc sort data = allmean; by lmomr; run;
proc means data = allmean noprint;
by lmomr;
var fmret;
output out = summary(drop=_TYPE_ _FREQ_) mean = mean t = t;
run;

data summary; set summary; J = &J.; K = &K.; run;

data results; set results summary; run;
%mend;

data results;

run;

%mom(3,3);
%mom(3,6);
%mom(3,9);
%mom(3,12);

%mom(6,3);
%mom(6,6);
%mom(6,9);
%mom(6,12);

%mom(9,3);
%mom(9,6);
%mom(9,9);
%mom(9,12);

%mom(12,3);
%mom(12,6);
%mom(12,9);
%mom(12,12);

proc print data = results; run;
