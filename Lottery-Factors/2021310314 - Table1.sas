/*****Step0:建立逻辑库*****/
/***建立逻辑库***/
%let path=D:\Review of MAX;
libname MAX "&Path\Data";

/********************************************************************************************************************************************************************
													构造EW Portfolios的Average Return与Four Factor Alpha
********************************************************************************************************************************************************************/
/*******************************STAGE1：得到每只股票每个月最大的收益MAX*******************************/
/*查看数据集*/
proc sort data = Max.Crspdaily out=A1;
  by Permno Date;
run;

data A1_1;
  set A1;
  Year = year(Date);
  Month = month(Date);
  keep Permno Year Month Ret;
run;

/*首先，找出每个Permno在每年，每月中的最大Ret*/
PROC SQL;
  create table Max_Ret as
  select Permno,
		 Year,Month,
		 max(Ret) as Max_Ret
  from A1_1
  group by Permno, Year, Month;
QUIT;
/*然后，将每只股票的所有时间的Max_Ret滞后一期以对应收益*/
DATA A2;
  set MAX_Ret;
  by Permno;
  Max_Ret = lag(MAX_Ret);
  if first.Permno then MAX_RET=.;
RUN;


/*******************************STAGE2：在每年每月，按照上个月的MAX对股票进行分组,并计算平均收益*******************************/
/***Step1:构建MAX分组前样本***/
DATA A2_1;
  set A2;
  if (Year > 1962 or (Year = 1962 and Month >= 7)) and (Year < 2005 or (Year = 2005 and Month <= 12));	
RUN;

/***Step2:将股票的MAX与收益数据合并***/
/*从Crspmonthly中读取股票的月回报数据*/
DATA A3;
SET MAX.Crspmonthly;
	Year=Year(Date);
	Month=Month(Date);
KEEP Permno Ret Year Month;
RUN;
/*将股票的月收益率与股票的MAX对应的分组信息合并*/
PROC SORT data=A3;
  BY Year Month Permno;
RUN;
PROC SORT data=A2_1;
  BY Year Month Permno;
RUN;
DATA A4;
  merge A2_1 (in=a) A3 (in=b);
  by Year Month Permno;
  if a;
RUN;

/***Step3:对样本按照MAX进行分组***/
PROC RANK data=A4 out=A4_1 groups=10;
   by Year Month;
   var Max_ret;
   ranks Group;
RUN;
DATA A4_2;
SET A4_1;
	Group = Group+1; LABEL Group='Max_Ret_Group';
RUN;

/***Step4:分别按照年月、分组计算各个组合中所有股票的月平均收益***/
/*按照每年，每月，对股票回报进行排序*/
PROC SORT DATA=A4_2 OUT=A5_1;
 by Year Month Group;
 where not missing(Group) and not missing(Ret);  /*去除空的数据*/
RUN; 
PROC SORT DATA=A4_2 OUT=A5_2;
 by Group;
 where not missing(Group) and not missing(Ret);  /*去除空的数据*/
RUN; 
/*分别按照年月、分组计算各个组合的平均收益*/
PROC MEANS data=A5_1 mean noprint;
   by Year Month Group;
   var Ret;
   output out=means_1 mean=Mean_Ret;
RUN;

PROC MEANS data=A5_2 mean noprint;
   class Group;
   var Ret;
   output out=means_2 mean=Mean_Ret;
RUN;


/*******************************STAGE3：利用股票收益进行FF4因子回归*******************************/
/***Step1：提取回归数据***/
/*股票分组月回报与因子数据*/
DATA A6;
  set Means_1;
  keep Year Month Group _FREQ_ Mean_ret;
RUN;
DATA Factors;
  set MAX.Ff3monthly1960_2005;
  Year = year(Dateff);
  Month = month(Dateff);
  drop Dateff;
RUN;
DATA A6_1;
  merge A6 (in=a) Factors (in=b);
  by Year month;
  if a;
RUN;
DATA A6_2;
  set A6_1 (rename = (Mean_ret = Mean_Exret));
  Mean_Exret=Mean_Exret-RF;
  drop Rf;
RUN;

/***Step2：进行回归分析***/
PROC SORT DATA=A6_2 OUT=A6_3;
  by Group;
RUN;
PROC REG data=A6_3 OUTEST=Regression_EV;
  model Mean_Exret = MKTRF SMB HML UMD;
  by Group;
RUN;


/*******************************STAGE4：构造收益差额序列*******************************/
/*两个分组在年份Y月份M的平均收益序列*/
DATA Diff_1;
  set A4_2;
  where Group=1;
RUN;
DATA Diff_10;
  set A4_2;
  where Group=10;
RUN;
PROC MEANS DATA=Diff_1 noprint;
  by Year Month;
  var RET;
  output out=Diff_Mean_1(keep=Year Month Mean_Ret_1) mean=Mean_Ret_1;
RUN;
PROC MEANS DATA=Diff_10 noprint;
  by Year Month;
  var RET;
  output out=Diff_Mean_10(keep=Year Month Mean_Ret_10) mean=Mean_Ret_10;
RUN;
PROC SQL;
CREATE table Diff_10M1 as
  select a.Year, a.Month, b.Mean_Ret_10-a.Mean_Ret_1 as Ret_10M1
  from Diff_Mean_1 as a left join Diff_Mean_10 as b
  on a.Year=b.Year and a.Month=b.Month;
QUIT;
/*求时间序列平均，获得t值*/
PROC MEANS DATA=Diff_10M1 noprint;
  var RET_10M1;
  output out=Diff_Mean1(Keep=Diff_Mean) mean=Diff_Mean;
RUN;
ODS output ParameterEstimates=Diff_T1;
PROC AUTOREG DATA=Diff_10M1;
   model Ret_10M1 = /covest=neweywest(gamma=0, rate=0, constant=6);	/*这里把Var对常数回归，为了得到Newey-West调整后的t值，一般滞后阶数设为6*/
RUN;
ODS output close;
PROC DATASETS noprint; delete Diff_1 Diff_10 Diff_Mean_1 Diff_Mean_10; RUN;
/*对四因子模型进行回归，获得alpha序列的t值*/
DATA Diff_Reg;
  merge Diff_10M1(in=a) Factors(in=b);
  by Year Month;
  if a;
RUN;
PROC REG DATA=Diff_Reg outest=Diff_PE;
  by Year Month;
  model Ret_10M1 = MKTRF SMB HML UMD;
RUN;
/*提取截距*/
Data Diff_Intcep;
  set Diff_PE;
  keep intercept;
RUN;
/*求取截距序列的均值与Newey-West调整t值*/
ODS output ParameterEstimates=Diff_T2;
PROC AUTOREG DATA=Diff_Intcep;
   model intercept = /covest=neweywest(gamma=0, rate=0, constant=6);	/*这里把Var对常数回归，为了得到Newey-West调整后的t值，一般滞后阶数设为6*/
RUN;
ODS output close;
PROC MEANS DATA=Diff_Intcep noprint;
  var Intcep;
  output out = Diff_Intcep mean=Intcep;
RUN;
DATA Diff_T2;
  set Diff_T2;
  keep tvalue;
RUN;
/*汇总我们需要的数据*/
DATA Diff_EV;
  merge Diff_T1(keep=tvalue rename=(tvalue=t_Ave)) Diff_T2(keep=tvalue rename=(tvalue=t_alpha)) Diff_Mean(keep=Diff_Mean) Diff_Intcep(keep=intcep);
RUN;
PROC DATASETS noprint; delete Diff_Reg Diff_PE Diff_T1 Diff_T2; RUN;



/********************************************************************************************************************************************************************
													构造VW Portfolios的Average Return与Four Factor Alpha
********************************************************************************************************************************************************************/
/*******************************STAGE1：计算数据MktCap与MktSize，进而计算平均收益*******************************/
/***Step1 计算数据的市值***/
/*读取CRSP数据*/
DATA B1;
  set MAX.Crspmonthly;
  Year = year(Date);
  Month = month(Date);
  drop Date SHRCD EXCHCD SICCD VOL VWRETD;/*去除不用的变量*/
RUN;
/*根据因子修正CRSP中的股票数据*/
DATA B1_1;
  set B1;
  PRC = abs(PRC)/CFACPR;
  SHROUT = SHROUT*CFACSHR*1000;/*原单位为千股*/
RUN;
PROC SQL;
  CREATE table B1_2 as
  select PERMNO, Year, Month, RET, (PRC*SHROUT)/1000000 as MktCap, log((PRC*SHROUT)/1000000) as MktSize/*原单位为百万*/
  from B1_1;
QUIT;
/*参考原文献，将该指标滞后一期*/
PROC SORT DATA=B1_2;
  by PERMNO Year Month;
RUN;
DATA B1_3;
  set B1_2;
  MktCap = lag(MktCap);
  MktSize = lag(MktSize);
  if first.PERMNO then do;
    MktCap = .;
    MktSize = .;
  end;/*每只股票头一个月的MktCap与MktSize为缺失值*/
RUN;

/***Step2:将市值加入分组数据，并计算平均收益***/
/*读取分组股票数据：同过程A2_1*/
DATA B2;
  set A2_1;
RUN;
/*将股票分组数据与市值数据合并*/
PROC SORT DATA=B1_3;
  by PERMNO Year Month;
RUN;
PROC SORT DATA=B2;
  by PERMNO Year Month;
RUN;
DATA B3;
  merge B1_3(in=a) B2(in=b);
  by PERMNO Year Month;
RUN;
/*剔除缺失值*/
DATA B3_1;
  set B3;
  if cmiss(of _all_)=0;
RUN;

/***Step3:对分组计算加权平均***/
/*对数据进行分组*/
PROC SORT DATA=B3_1;
  by Year Month;
RUN;
PROC RANK DATA=B3_1 OUT=B3_2 groups=10;
  by Year Month;
  var Max_Ret;
  ranks Group;
RUN;
DATA B3_3;
SET B3_2;
	Group = Group+1; LABEL Group='Max_Ret_Group';	/*调整分组代码*/
RUN;

/*按照每年，每月，对股票回报进行排序*/
PROC SORT DATA=B3_3 OUT=B4_1;
 by Group Year Month;
RUN; 
PROC SORT DATA=B3_3 OUT=B4_2;
 by Group;
RUN; 
/*分别按照年月、分组计算各个组合的平均收益*/
PROC MEANS data=B4_1 noprint;
   by Group Year Month;
   var Ret;
   weight MktSize;
   output out=Means_3 mean=Mean_Ret_VW;
RUN;
PROC MEANS data=B4_2 noprint;
   class Group;
   var Ret;
   weight MktSize;
   output out=Means_4 mean=Mean_Ret_VW;
RUN;


/*******************************STAGE2：利用股票收益进行FF4因子回归*******************************/
/***Step1：提取回归数据***/
/*股票分组月回报与因子数据*/
DATA B5;
  set Means_3;
  keep Year Month Group _FREQ_ Mean_ret_VW;
RUN;
DATA Factors;
  set MAX.Ff3monthly1960_2005;
  Year = year(Dateff);
  Month = month(Dateff);
  drop Dateff;
RUN;
/*数据合并*/
PROC SORT DATA=B5;
  by Year Month;
RUN;
DATA B5_1;
  merge B5 (in=a) Factors (in=b);
  by Year month;
  if a;
RUN;
DATA B5_2;
  set B5_1 (rename = (Mean_ret_VW = Mean_Exret_VW));
  Mean_Exret_VW = Mean_Exret_VW-RF;
  drop Rf;
RUN;

/***Step2：进行回归分析***/
PROC SORT DATA=B5_2 OUT=B5_3;
  by Group;
RUN;
PROC REG data=B5_3 OUTEST=Regression_VW noprint;
  model Mean_Exret_VW = MKTRF SMB HML UMD;
  by Group;
RUN;


/*******************************STAGE3：构造收益差额序列*******************************/
/*两个分组在年份Y月份M的平均收益序列*/
DATA Diff_1_2;
  set B3_3;
  where Group=1;
RUN;
DATA Diff_10_2;
  set B3_3;
  where Group=10;
RUN;
PROC MEANS DATA=Diff_1_2 noprint;
  by Year Month;
  var RET;
  output out=Diff_Mean_1_2(keep=Year Month Mean_Ret_1_2) mean=Mean_Ret_1_2;
RUN;
PROC MEANS DATA=Diff_10_2 noprint;
  by Year Month;
  var RET;
  output out=Diff_Mean_10_2(keep=Year Month Mean_Ret_10_2) mean=Mean_Ret_10_2;
RUN;
PROC SQL;
CREATE table Diff_10M1_2 as
  select a.Year, a.Month, b.Mean_Ret_10_2-a.Mean_Ret_1_2 as Ret_10M1_2
  from Diff_Mean_1_2 as a left join Diff_Mean_10_2 as b
  on a.Year=b.Year and a.Month=b.Month;
QUIT;
/*求时间序列平均，获得t值*/
PROC MEANS DATA=Diff_10M1_2 noprint;
  var RET_10M1_2;
  output out=Diff_Mean1_2(Keep=Diff_Mean) mean=Diff_Mean;
RUN;
ODS output ParameterEstimates=Diff_T1_2;
PROC AUTOREG DATA=Diff_10M1_2;
   model Ret_10M1_2 = /covest=neweywest(gamma=0, rate=0, constant=6);	/*这里把Var对常数回归，为了得到Newey-West调整后的t值，一般滞后阶数设为6*/
RUN;
ODS output close;
PROC DATASETS noprint; delete Diff_1_2 Diff_10_2 Diff_Mean_1_2 Diff_Mean_10_2; RUN;
/*对四因子模型进行回归，获得alpha序列的t值*/
DATA Diff_Reg_2;
  merge Diff_10M1_2(in=a) Factors(in=b);
  by Year Month;
  if a;
RUN;
PROC REG DATA=Diff_Reg_2 outest=Diff_PE_2;
  by Year Month;
  model Ret_10M1_2 = MKTRF SMB HML UMD;
RUN;
/*提取截距*/
Data Diff_Intcep_2;
  set Diff_PE_2;
  keep intercept_2;
RUN;
/*求取截距序列的均值与Newey-West调整t值*/
ODS output ParameterEstimates=Diff_T2_2;
PROC AUTOREG DATA=Diff_Intcep_2;
   model intercept_2 = /covest=neweywest(gamma=0, rate=0, constant=6);	/*这里把Var对常数回归，为了得到Newey-West调整后的t值，一般滞后阶数设为6*/
RUN;
ODS output close;
PROC MEANS DATA=Diff_Intcep_2 noprint;
  var Intcep;
  output out = Diff_Intcep_2 mean=Intcep_2;
RUN;
DATA Diff_T2_2;
  set Diff_T2_2;
  keep tvalue_2;
RUN;
/*汇总我们需要的数据*/
DATA Diff_EV_2;
  merge Diff_T1_2(keep=tvalue rename=(tvalue=t_Ave)) Diff_T2_2(keep=tvalue rename=(tvalue=t_alpha)) Diff_Mean_2(keep=Diff_Mean) Diff_Intcep_2(keep=intcep);
RUN;
PROC DATASETS noprint; delete Diff_Reg Diff_PE Diff_T1 Diff_T2; RUN;



/********************************************************************************************************************************************************************
																构造投资组合的Average MAX
********************************************************************************************************************************************************************/
/*****AVERAGE MAX—追溯到过程A4_2*******/
PROC SORT data=A4_2 out=C1;
  by Group;
RUN;
PROC MEANS data=C1 noprint;
  var Max_Ret;
  by Group;
  output out=C1_1 mean=mean_MAX;
RUN;
