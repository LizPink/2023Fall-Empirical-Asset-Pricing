libname code "C:\Users\zhang\Desktop\Robinhood";

* Robinhood sample period: May 2 2018 and August 13 2020;
data data; set code.robinhood;
if ticker ne " ";
year   = substr(timestamp,1,4);
month  = substr(timestamp,6,2);
day    = substr(timestamp,9,2);
hour   = substr(timestamp,12,2);
minute = substr(timestamp,15,2);
second = substr(timestamp,18,2);
run;
data data; set data;
date = mdy(month,day,year); format date date9.; 
time = hms(hour,minute,second); format time time8.;
weekday = weekday(date)-1; 
drop month day year;
drop hour minute second;
run;


* 1. user_close and userchg;
* users_close, measure the total number of users in a stock prior to the close of trading (4pm ET) but after 2pm;
* daily changes in users_close (userchg) or the ratio of users_close on consecutive days (userratio);
* rh_chgratio, which is the percentage change in users from day t-1 to t;
* users_last, the last reported user count for a stock on each day (regardless of the time of reporting);
proc sort data = data; by ticker date time; run;
data data1; set data;
if "14:00:00"t<= time <= "16:00:00"t;
run;
data data1; set data1;
by ticker date time;
if last.date;
run;
data data2; set data;
by ticker date time;
if last.date;
run;
data data1; set data1; rename users_holding = users_close; rename time = time_close;run;
data data2; set data2; rename users_holding = users_last;  rename time = time_last; run;
proc sql;
create table data3
as select a.ticker,a.date,a.weekday,a.users_last,a.time_last, b.users_close,b.time_close
from data2 as a left join data1 as b
on a.ticker = b.ticker and a.date = b.date;
quit;


* daily chage;
data dx; set data3; keep date; run;
proc sort data = dx nodupkey; by date; run;
data dx; set dx; dx = _N_; run;
proc sort data = dx; by date; run;
proc sort data = data3; by date; run;
data data3; merge data3(in=ina) dx;
by date;
if ina;
run;

proc sql;
create table data4
as select a.*, b.users_close as l1_users_close, b.users_last as l1_users_last
from data3 as a left join data3 as b
on a.ticker = b.ticker and a.dx = b.dx + 1;
quit;

data data4; set data4;
userratio1 = users_close/l1_users_close;
userratio2 = users_last /l1_users_last;
run;


* 2. Herding events;
* Identify stocks with an increase in users (userratio > 1) and at least 100 users entering the day(users_close(t-1)>=100);
* Among these stocks, we sort stocks based on the day t userratio and identify the top 0.5% of stocks as Robinhood herding stocks, indicator rh_herd;
* We idenfity 4,884 herding events (about 9 per day on average), which occur in 2,301 unique tickers;
proc sort data = data4; by date; run;
proc univariate data = data4 noprint;
where userratio1 > 1 and l1_users_close >= 100;
by date;
var userratio1;
output out = pct1 pctlpts = 99.5 pctlpre = p;
run;
proc univariate data = data4 noprint;
where userratio2 > 1 and l1_users_last >= 100;
by date;
var userratio2;
output out = pct2 pctlpts = 99.5 pctlpre = p;
run;
data pct1; set pct1; rename p99_5 = p99_5_v1; run;
data pct2; set pct2; rename p99_5 = p99_5_v2; run;

data RHherd; merge data4(in=ina) pct1 pct2;
by date;
if ina;
run;
data RHherd; set RHherd;
if userratio1 > 1 and l1_users_close >= 100 and userratio1 > p99_5_v1 then rh_herd1 = 1; else rh_herd1 = 0;
if userratio2 > 1 and l1_users_last  >= 100 and userratio2 > p99_5_v2 then rh_herd2 = 1; else rh_herd2 = 0;
run;
data code.RHherd; set RHherd; run;


* 3. CRSP predict return;
data crsp; set code.crsp; 
if "02May2018"d <= date <= "13Aug2020"d;
run;
proc sql;
create table crsp
as select a.*, b.dx
from crsp as a left join dx as b
on a.date = b.date;
quit;

proc sql;
create table final
as select b.*, a.rh_herd1, a.rh_herd2,(a.userratio1-1) as chgratio1, (a.userratio2-1) as chgratio2
from rhherd as a left join crsp as b
on a.ticker = b.tsymbol and a.dx + 1 = b.dx;
quit;

* Fama-MacBeth;
%macro fm(Robin);
proc sort data = final; by date; run;
proc reg data = final outest = pe adjrsq noprint; by date; model ret = &Robin.; quit;
proc transpose data = pe out = pe1; by date; var Intercept &Robin. _ADJRSQ_; run;
proc sort data = pe1; by _NAME_; run;

ods output parameterestimates = nw1; 
ods listing close;
proc model data = pe1;
by _NAME_;
instrument/intonly;
col1 = a;
fit col1/gmm kernel = (bart,%eval(5+1),0) vardef = n;
quit;

data nw1; set nw1;
if _NAME_ = "Intercept" then order = 0;
if _NAME_ = "&Robin." then order = 1;
if _NAME_ = "_ADJRSQ_" then order = 9;
drop EstType Parameter StdErr Probt DF;
run;

proc sort data = nw1; by order; run;
data nw1; length Robin $10.; set nw1; Robin = "&Robin."; run;
data all1; set all1 nw1; run; 
%mend;

data all1;

run;
%fm(rh_herd1);
%fm(rh_herd2);
%fm(chgratio1);
%fm(chgratio2);

proc print data = all1; run;

