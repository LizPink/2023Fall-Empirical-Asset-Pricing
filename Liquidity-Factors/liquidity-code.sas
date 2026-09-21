libname code "C:\Users\zhang\Desktop\Liquidity\data";

* 1964-1997;
* NYSE stocks;
* Common stocks;

data code.crspday_new; set code.crspday;
if shrcd in (10,11) and exchcd in (1);
if 1964<=year(date)<=1997;
keep permno date prc vol ret;
run;

data code.crspmonthly_new; set code.crspmonthly;
if shrcd in (10,11) and exchcd in (1);
if 1964<=year(date)<=1997;
keep permno date prc vol ret;
run;



* Step 1. Amihud illiquidity measure;
* per stock per year, y-1;
data crspday; set code.crspday_new; 
amihud = abs(ret)/abs(prc*vol)*1000000; 
year = year(date);
run;
proc sort data = crspday; by permno year; run;
proc means data = crspday noprint;
by permno year;
var amihud;
output out = amihud(drop=_TYPE_ _FREQ_) mean = amihud_stock_year n = amihud_ndays;
run;


* Step 2. Filters;
* Filter1: The stock has return and volume data for more than 200 days during year y-1;
* Filter2: The stock price is greater than $5 at the end of year y-1;
* Filter3: The stock has data on market cap at the end of y-1;
proc means data = crspday noprint;
by permno year;
var ret;
output out = ndays (drop=_TYPE_ _FREQ_) n = ndays;
run;

data crspmonth; set code.crspmonthly;
year = year(date);
marketcap = abs(prc) * shrout / 1000; *million;
prc = abs(prc);
keep permno year date prc marketcap;
run;
proc sort data = crspmonth; by permno year date; run;
data prc_marketcap; set crspmonth;
by permno year date;
if last.year;
run;

proc sql;
create table amihud
as select a.*, b.ndays
from amihud as a left join ndays as b
on a.permno = b.permno and a.year = b.year;
quit;
proc sql;
create table amihud 
as select a.*, b.prc, b.marketcap
from amihud as a left join prc_marketcap as b
on a.permno = b.permno and a.year = b.year;
quit;

data amihud; set amihud;
if ndays > 200;
if prc ne .;
if marketcap ne .;
run;

* Filter 4: Excluded are stocks whose ILLIQ is at the extreme 1% upper and lower tails 
of the respective distribution for the year;
proc sort data = amihud; by year; run;
proc means data = amihud noprint;
by year;
var amihud_stock_year;
output out = amihud_extreme(drop=_TYPE_ _FREQ_) p1 = p1 p99 = p99;
run;
proc sql;
create table amihud
as select a.*, b.p1, b.p99
from amihud as a left join amihud_extreme as b
on a.year = b.year;
quit;
data amihud; set amihud;
if amihud_stock_year > p99 then delete;
if amihud_stock_year < p1 then delete;
run;




* Step 3. Mean adjusted Illiquidity;
proc sort data = amihud; by year; run;
proc means data = amihud noprint;
by year;
var amihud_stock_year;
output out = amihud_market(drop=_TYPE_ _FREQ_) mean = amihud_market;
run;
proc sql;
create table amihud
as select a.*, b.amihud_market
from amihud as a left join amihud_market as b
on a.year = b.year;
quit;
data amihud; set amihud;
amihud_stock_year_mean_adjust = amihud_stock_year / amihud_market;
run;

* Step 4. Fama MacBeth return;
data data; set code.crspmonthly;
year = year(date);
marketcap = abs(prc) * shrout / 1000; *million;
keep permno year date ret marketcap;
run;
* from previous year;
proc sql;
create table data 
as select a.*, b.amihud_stock_year_mean_adjust
from data as a left join amihud as b
on a.permno = b.permno and a.year = b.year + 1;
quit;
data data; set data; if amihud_stock_year_mean_adjust ne .; run;

proc sort data = data; by date; run;
proc reg data = data outest = pe adjrsq noprint;
by date;
model ret = amihud_stock_year_mean_adjust;
quit;
proc transpose data = pe out = pe2;
by date;
var Intercept amihud_stock_year_mean_adjust _ADJRSQ_;
run;
proc sort data =  pe2; by _NAME_ ; run;

ods output parameterestimates = nw1; 
ods listing close;
proc model data = pe2;
by _NAME_;
instrument/intonly;
col1 = a;
fit col1/gmm kernel = (bart,5,0) vardef = n;
quit;





