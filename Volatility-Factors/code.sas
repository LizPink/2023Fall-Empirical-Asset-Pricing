libname code "C:\Users\zhang\Desktop\IVOL\data";

* 1964-2000;
* Common stocks;

/*
data code.crspday_new; set code.crspday;
if shrcd in (10,11) and exchcd in (1,2,3);
if 1963<=year(date)<=2000;
keep permno date ret;
run;

data code.crspmonthly_new; set code.crspmonthly;
if shrcd in (10,11) and exchcd in (1,2,3);
if 1963<=year(date)<=2000;
size = abs(prc) * shrout / 1000; *million;
keep permno date size ret;
run;
*/

data ff3day;          set code.ff3day; run;
data crspday_new;     set code.crspday_new; 
yearmonth = intnx("month",date,0,'e'); format yearmonth date9.; 
run;
data crspmonthly_new; set code.crspmonthly_new; 
yearmonth = intnx("month",date,0,'e'); format yearmonth date9.; 
run;

proc sort data = crspday_new; by date permno; run;
proc sort data = ff3day;      by date; run;

data crspday_new; merge crspday_new(in=ina) ff3day;
by date;
if ina;
run;

data crspday_new; set crspday_new;
exret = ret - rf;
run;

data mx; set crspday_new; keep yearmonth; run;
proc sort data = mx nodupkey; by yearmonth; run;
data mx; set mx;
mx = _N_;
run;
proc sort data = crspday_new; by yearmonth; run;
proc sort data = mx; by yearmonth; run;
proc sort data = crspmonthly_new; by yearmonth; run;
data crspday_new; merge crspday_new(in=ina) mx;
by yearmonth;
if ina;
run;
data crspmonthly_new; merge crspmonthly_new(in=ina) mx;
by yearmonth;
if ina;
run;


proc sort data = crspday_new; by mx permno; run;
proc reg data = crspday_new outest = pe noprint;
by mx permno;
model exret = mkt_rf smb hml;
output out = res r = r;
quit;

* sqrt root of var(resid);
proc means data = res noprint;
by mx permno;
var r;
output out = ivol(drop=_TYPE_ _FREQ_) n = ndays std = ivol;
run;


proc sql;
create table data
as select a.*, b.ivol as l1ivol
from crspmonthly_new as a left join ivol as b
on a.permno = b.permno and a.mx = b.mx + 1;
quit;
proc sql;
create table data
as select a.*, b.size as l1size
from data as a left join crspmonthly_new as b
on a.permno = b.permno and a.mx = b.mx + 1;
quit;

data data; set data;
if l1ivol ne .;
run;

* rank and portfolios;
proc sort data = data; by mx; run;
proc rank data = data out = data groups = 5;
by mx;
var l1ivol;
ranks rivol;
run;

* Value weight;
proc sort data = data; by mx rivol; run;
proc means data = data noprint;
weight l1size;
by mx rivol;
var ret;
output out = summary mean = mean;
run;

proc transpose data = summary out = summary;
by mx;
id rivol;
var mean;
run;

data summary; set summary;
_99 = _4 - _0;
run;

proc means data = summary mean t;
var _0 _1 _2 _3 _4 _99;
run;








