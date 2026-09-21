/*****Step0:建立逻辑库*****/
/***建立逻辑库***/
%LET path=D:\Review of MAX;
LIBNAME MAX "&Path\Data";
/********************************************************************************************************************************************************************
																TABLE3 构造指标变量
********************************************************************************************************************************************************************/
/*注：在Table2部分，Ret类变量在原文中应该是被放大了100倍，例如0.23=>23，同时注意其他单位换算*/
/***编写统一的宏***/
/*宏1：去除缺失值*/
%MACRO NotNull(InputData,Var);	/*对数据集InputData，去除变量Var为空的观测*/
DATA &InputData;
  set &InputData;
  &Var = &Var+0; /*为了防止数据集有不合理的字母值C等导致无法去除的情况出现*/
  if &Var ^=.;
RUN;
%MEND;
/***构建MAX***/
DATA D1;
  set MAX.Crspdaily;
  Year = year(Date);
  Month = month(Date);
  keep Permno Date Year Month Ret;
RUN;
PROC SORT data = D1;
  by Permno Date;
RUN;
PROC SQL;
  CREATE table MAX_0 as
    select Permno,
		   Year,Month,
		   max(Ret) as Max
    from D1
    group by Permno, Year, Month;
QUIT;
DATA MAX;
  set MAX_0;
  MAX = MAX*100;
  if MAX^=.;
RUN;
%NotNull(MAX,MAX);	/*删除缺失MAX的观测*/
PROC DATASETS noprint; delete D1; RUN;

/***构建Lagged_MAX***/
DATA MAXlag_0;
  set MAX;
  by PERMNO Year Month;
  MAX_Lagged = lag(MAX);
  if first.PERMNO then MAX_Lagged = .; /*每只股票头一个月的上一个月MAX_Lagged为缺失值*/
RUN;
DATA Maxlag;
  set Maxlag_0;
  if Max_Lagged^=.;
  keep PERMNO Year Month Max_lagged;
RUN;
DATA Lagged_MAX;
  set MAX_0;
  MAX = lag(MAX);
  MAX = MAX*100;
RUN;
%NotNull(MAX,MAX);	/*删除缺失MAX的观测*/
PROC DATASETS noprint; delete MAX_0 MAXlag_0; RUN;

/***构建BETA与IVOL***/
/*整理数据集*/
PROC SQL;
  CREATE table CrspDaily as
    select PERMNO, Date, RET, VWRETD, year(Date) as Year, month(Date) as Month
	from MAX.Crspdaily
	group by PERMNO, Date;
QUIT;
PROC SQL;
  CREATE table FF4Daily as
    select Date, RF, year(Date) as Year, month(Date) as Month
	from MAX.FF3daily1960_2005
	group by date;
QUIT;
/*数据合并*/
PROC SORT DATA=CrspDaily;
  by Date;
RUN;
PROC SORT DATA=FF4Daily;
  by Date;
RUN;
DATA E1;
  merge CrspDaily(in=a) FF4Daily(in=b);
  by Date;
  if a;
RUN;
/***构建BETA***/
/*构建滞后一期、当期、提前一期的收益率数据*/
PROC SORT DATA=E1;
  by PERMNO Date;
RUN;
DATA Lagged_Beta_0;
  set E1;
  ExRet = Ret-RF;
  ExVwretd = Vwretd-RF;
  drop Ret Vwretd Rf;
RUN;
DATA Lagged_Beta;
  set Lagged_Beta_0;
  Lagged_ExVwretd = lag(ExVwretd);
  by PERMNO Year Month;
  if not first.Month;
RUN;
DATA Lead_Beta_0;
  merge E1 E1(firstobs=2 Keep=Ret Vwretd Rename=(Ret=Lead_Ret Vwretd=Lead_Vwretd));	/*手动提前*/
  Lead_ExVwretd = Lead_Vwretd-Rf;
  drop Lead_Ret Lead_Vwretd Ret Vwretd Rf;
RUN;
DATA Lead_Beta;
  set Lead_Beta_0;
  by PERMNO Year Month;
  if not last.Month;
RUN;
PROC DATASETS noprint;
  delete Lagged_Beta_0 Lead_Beta_0;	/*内存不够用*/
RUN;
PROC SORT DATA = Lagged_Beta;
  by PERMNO Date;
RUN;
PROC SORT DATA = Lead_Beta;
  by PERMNO Date;
RUN;
DATA BETA_Ret;
  merge Lagged_Beta(in=a) Lead_Beta(in=b);
  by PERMNO Date;
  if (a and b);
RUN;
/*计算BETA*/
DATA BETA_REG;
  set BETA_Ret;
  keep PERMNO Year Month ExRet ExVwretd Lagged_ExVwretd Lead_ExVwretd;
  if cmiss(of _all_)=0;
RUN;
PROC SORT DATA=BETA_REG;
  by Permno Year Month;
RUN;
PROC REG DATA = BETA_REG outest=PE_BETA noprint;
  by PERMNO Year Month;
  model Exret = ExVwretd Lagged_ExVwretd Lead_ExVwretd;
RUN;
DATA BETA;
  set PE_BETA;
  Beta = ExVwretd + Lagged_ExVwretd + Lead_ExVwretd;
  keep PERMNO Year Month Beta;
RUN;
/***构建IVOL***/
/*构建回归数据集*/
DATA IVOL_Reg_0;
  set E1;
  ExRet = (Ret-RF)*100;
  ExVwretd = (Vwretd-RF)*100;
  keep PERMNO Year Month ExRet ExVwretd;
  if cmiss(of _all_)=0;
RUN;
/*回归，收集残差*/
PROC SORT DATA=IVOL_Reg_0; by PERMNO Year Month; RUN;
PROC REG DATA=IVOL_Reg_0 noprint;
  by PERMNO Year Month;
  model ExRet = ExVwretd;
  output out = IVOL_Reg  r=IVOL_res;
RUN;
DATA IVOL_Res;
  set IVOL_Reg;
  keep PERMNO Year Month IVOL_res;
RUN;
/*计算股票i在月份m的残差的标准差，得到IVOL*/
PROC MEANS DATA=IVOL_Res std noprint;
  by PERMNO Year Month;
  var IVOL_res;
  output out=IVOL std=IVOL;
RUN;
DATA IVOL;
  set IVOL;
  IVOL = IVOL*10;	/*单位换算*/
  drop _Freq_ _Type_;
RUN;
PROC DATASETS noprint; delete E1 Crspdaily FF4Daily Lagged_BETA Lead_Beta BETA_RET BETA_REG IVOL_REG_0 IVOL_REG IVOL_Res; RUN;

/***构建Size***/
/*读取CRSP数据*/
DATA F1;
  set MAX.Crspmonthly;	/*按照Table1的构建方法即可*/
  Year = year(Date);
  Month = month(Date);
  drop Date SHRCD EXCHCD SICCD VOL VWRETD;/*去除不用的变量*/
RUN;
/*根据因子修正CRSP中的股票数据*/
DATA F1_1;
  set F1;
  PRC = abs(PRC)/CFACPR;
  SHROUT = SHROUT*CFACSHR*1000;/*原单位为千股*/
RUN;
PROC SQL;
  CREATE table F1_2 as
  select PERMNO, Year, Month, RET, (PRC*SHROUT)/1000000 as MktCap, log((PRC*SHROUT)/1000000) as MktSize/*原单位为百万*/
  from F1_1;
QUIT;
/*参考原文献，将该指标滞后一期*/
PROC SORT DATA=F1_2;
  by PERMNO Year Month;
RUN;
DATA Size;
  set F1_2;
  keep PERMNO Year Month MktCap MktSize;
RUN;
PROC DATASETS noprint; delete F1 F1_1 F1_2; RUN;


/***构建BM***/
/***计算普通股的账面价值***/
DATA G1;
  set MAX.Funda1959_2005;
  where datafmt='STD' and indfmt='INDL';	/*如果缺少股东权益（SEQ），则无法计算账面市值比*/
  if SEQ^=.;
RUN;
DATA BookValue_01;
  set G1;
  keep SEQ TXDB ITCB PSTKRV PSTKL PSTK gvkey datadate fyear cusip SICH;
RUN;
DATA BookValue_02;
  set BookValue_01;
  if PSTKRV^=0 then BVPS=PSTKRV;
  else if PSTKL^=0 then BVPS=PSTKL;	/*计算优先股价值BVPS*/
  else if PSTK^=0 then BVPS=PSTK;
  else BVPS=0;
  BE=.;	/*新增一列BE用于后续计算*/
RUN;
DATA BookValue_03;	/*替换缺失值为0*/
  set BookValue_02;
  array vars[*] _numeric_;
    do i = 1 to dim(vars);
        if vars[i] = . then vars[i] = 0;
    end;
  drop i;
RUN;
DATA BookValue;
  set BookValue_03;
  drop SEQ TXDB ITCB PSTKRV PSTKL PSTK BVPS CUSIP SICH;
  BE = SEQ + TXDB + ITCB - BVPS;
RUN;


/***计算股票的市场价值***/
DATA G2;
  set MAX.Crspmonthly;
RUN;
DATA MktValue_01;
  set G2;
  Year = year(Date);
  Month = month(Date);
  keep PERMNO Year Month PRC SHROUT CFACPR CFACSHR;
RUN;
DATA MktValue_02;
  set MktValue_01;
  PRC = PRC/CFACPR;
  SHROUT = SHROUT*CFACSHR;
  ME = abs(PRC*SHROUT)/1000;
  drop CFACPR CFACSHR PRC SHROUD;
RUN;
/*计算股票每个月的市场价值（ME）*/
/*Step1:提取每年12月的ME值*/
DATA Dec_MktValue;
    set MktValue_02;
    where Month = 12; /* 选择12月的数据 */
    keep Permno Year ME; /* 保留所需变量 */
RUN;
PROC SORT DATA = Dec_MktValue nodupkey;by Permno Year ME; RUN;
/*Step2:将提取的数据与原始数据集合并*/
PROC SORT DATA=MktValue_02; by Permno Year Month; RUN;
PROC SORT DATA=Dec_MktValue; by Permno Year; RUN;
DATA MktValue_03;
    merge MktValue_02(in=a) Dec_MktValue(in=b rename=(ME=Dec_ME));
    by Permno Year;
    if a;
RUN;
/*Step3:使用12月的 ME 更新其他月份的ME*/
DATA MktValue;
    set MktValue_03;
    if Month ^= 12 then me = Dec_ME; /* 如果不是12月，更新 ME 值 */
    drop Dec_ME;
RUN;

/***将公司的ME与BE相匹配***/
DATA Link;
  set MAX.Ccmxpf_linktable;
  if linktype="LU" or linktype='LC';	/*选择LU或LC的观测*/
RUN;
PROC SQL;
  CREATE table Temp1 as
  select a.*, b.lpermno as Permno
  from BookValue as a left join Link as b
  on (a.gvkey = b.gvkey) and (b.LINKDT <= a.datadate) and (a.datadate <= b.LINKENDDT or missing(b.LINKENDDT));
QUIT;
PROC SORT DATA=Temp1 nodupkey; by Permno fyear; RUN;
PROC SORT DATA = Temp1; by Permno fyear descending datadate;RUN;	/*如果出现多个观测值，则取最新的*/
PROC SORT DATA = Temp1 nodupkey;by permno fyear; RUN;
/* 计算公司同期匹配的BE与ME，得到BM */
PROC SQL;
  CREATE table Temp2 as
  select a.Permno, a.Year, a.ME,
  b.gvkey, b.fyear,b.BE, b.BE/a.ME as BM
  from Dec_MktValue as a left join Temp1 as b
  on a.permno=b.permno and b.fyear=a.Year;
QUIT;
PROC SORT DATA = TEMP2 nodupkey; by Year Permno; RUN;
/*将BM合并到股票数据中*/
PROC SQL;
  create table BM
  as select a.Permno,a.Date,b.BM 
  from G2 as a left join Temp2 as b
  on a.Permno=b.Permno and year(a.Date)=b.Year+1;
QUIT;
DATA BM;set BM;
  Year = year(Date);
  Month = month(Date);
  if BM>=0;
  drop date;
run;

/***对BM进行缩尾处理***/
/*缩尾：每个月月度截面0.5%缩尾*/
PROC SORT DATA = BM;
  by Year Month BM;
RUN;
PROC UNIVARIATE DATA=BM noprint; 
  var BM; 
  by Year Month;
  output out=BM_pct1 pctlpre=p pctlpts=(0.5 99.5); 
RUN; 
PROC SQL;
  CREATE table BM_winsorized_0
  as select a.*,b.* 
  from BM as a left join BM_pct1 as b
  on a.Year = b.Year and a.Month=b.Month;
QUIT;
DATA BM_winsorized;
  set BM_winsorized_0; 
  if BM<p0_5 then BM=p0_5;
  if BM>p99_5 then BM=p99_5; 
  drop p0_5 p99_5;
RUN; 
PROC DATASETS noprint; delete G1 G2 MktValue_01 MktValue_02 MktValue_03 Temp1 Temp2 Link; RUN;


/***构建MOM***/
/*构建初始数据集*/
DATA H1;	/*股票i在时间t的MOM是从t-11至t-2的连续11个月的累计收益*/
  set MAX.CrspMonthly;
  Year = year(Date);
  Month = month(Date);
  Time = Year*12 + Month;	/*将时间转换为单调递增的连续值，便于计算动量*/
  Ret = Ret+0;
  if Ret ^=.;	/*这两行是为了剔除没有收益率的观测*/
  keep PERMNO Date Time Ret;
RUN;
PROC SORT DATA=H1;
  by PERMNO Time;
RUN;
/*计算累积收益率，进而计算股票动量数据*/
DATA MOM_01;
  set H1;
  by PERMNO Time;
  retain CulRet 1;
  retain Count 0;
  if first.PERMNO then do;
    CulRet=1;
	Count=0;
  end;
  CulRet = CulRet*(1+Ret);
  Count = Count+1;
RUN;
DATA MOM_02;
  set MOM_01;
  by PERMNO Time;
  MOM = (lag2(CulRet)/lag12(CulRet))-1;
RUN;
DATA MOM;
  set MOM_02;
  Year = year(Date);
  Month = month(Date);
  where Count >=13;	/*剔除观测个数Count小于13的股票，因为其没有完整的前12个月的数据*/
  keep PERMNO Year Month MOM;
RUN;
PROC DATASETS noprint; delete H1 MOM_01 MOM_02; RUN;

/***构建REV***/
DATA I1;	/*股票i在时间t的REV是t-1的收益率*/
  set MAX.Crspmonthly;
  Year = year(Date);
  Month = month(Date);
  Ret = Ret+0;
  keep PERMNO Year Month Ret;
RUN;
PROC SORT DATA=I1;
  by PERMNO Year Month;
RUN;
DATA REV;
  set I1;
  by PERMNO Year Month;
  REV = lag(Ret);
  REV = REV*100;
  if first.PERMNO then Ret=.;
  if REV ^=.;	/*剔除缺失REV的观测*/
  keep PERMNO Year Month Rev;
RUN;
PROC DATASETS noprint; delete I1; RUN;

/***构建ILLIQ***/
DATA J1;
  set MAX.Crspmonthly;	/*股票i在时间t的ILLIQ是t期的绝对收益率比上t期的交易量*/
  Year = year(Date);
  Month = month(Date);
RUN;
PROC SORT DATA=J1;
  by PERMNO Year Month;
RUN;
DATA ILLIQ;
  set J1;
  ILLIQ = (abs(Ret)/abs(PRC*VOL))*100*1000;
  keep PERMNO Year Month ILLIQ;
  if ILLIQ ^=.;	/*剔除缺失ILLIQ的观测*/
RUN;
PROC DATASETS noprint; delete J1; RUN;

/********************************************************************************************************************************************************************
																各指标对MAX进行回归
********************************************************************************************************************************************************************/
/***编写统一的宏***/
/*宏2：数据变量滞后*/
%MACRO Lag(InputData,Var,OutputData);	/*对数据集InputData，将变量Var滞后一期*/
PROC SORT DATA=&InputData;
  by PERMNO Year Month;
RUN;
DATA &OutputData;
  set &InputData;
  by PERMNO Year Month;
  &Var = lag(&Var);
  if first.PERMNO then &Var=.;
RUN;
%MEND;
/*宏3：限定时间范围*/
%MACRO TimeLimit(InputData,Year1,Month1,Year2,Month2);
DATA &InputData;
  set &InputData;
  if (Year > &Year1 or (Year = &Year1 and Month >= &Month1)) and (Year < &Year2 or (Year = &Year2 and Month <= &Month2));
RUN;
%MEND;
/*宏4：回归分析*/
%MACRO RegMean(InputData,Var,OutputData); /*对输入数据集InputData，与MAX合并，回归计算平均系数、Newey-Westt值与R^2*/
%Lag(&InputData,&Var,DataLag);

PROC SQL;
  CREATE table Table0 as
  select a.*,b.&Var
  from  Max as a inner join DataLag as b
  on a.PERMNO = b.PERMNO and a.Year=b.Year and a.Month=b.Month;
QUIT;

%NotNull(Table0,&Var);
%TimeLimit(Table0,1962,7,2005,12);

PROC SORT DATA = table0;
  by Year Month;
RUN;
PROC REG DATA=table0 outest=PE1 rsquare noprint;	/*这里采用普通回归，为了得到估计系数与R^2，存储在PE1中*/
   by Year Month;
   model MAX = &Var;
RUN;
ODS output ParameterEstimates=PE2;
PROC AUTOREG DATA=PE1;
   model &Var = /covest=neweywest(gamma=0, rate=0, constant=6);	/*这里把Var对常数回归，为了得到Newey-West调整后的t值，一般滞后阶数设为6*/
RUN;
ODS output close;

PROC MEANS DATA = PE1 mean noprint;
  var &Var;
  output out=Coef(drop=_type_ _freq_) mean=MeanCoef;
RUN;
PROC MEANS DATA = PE1 mean noprint;
  var _Rsq_;
  output out=Rsquare(drop=_type_ _freq_) mean=MeanRsquare;
RUN;
DATA PE2;
  set PE2;
  keep tvalue;
RUN;

DATA &OutputData;
  merge Coef Rsquare PE2;	/*整理过程数据，汇总到OutputData返回*/
RUN;
PROC DATASETS noprint; delete Datalag Table0 PE1 PE2 Coef Rsquare;quit;	/*删除过程变量，节省空间*/
%MEND;
%RegMean(MAXlag,MAX_Lagged,test1);
%RegMean(BETA,BETA,test2);
%RegMean(SIZE,MktSize,test3);
%RegMean(BM_winsorized,BM,test4);
%RegMean(MOM,MOM,test5);
%RegMean(REV,REV,test6);
%RegMean(ILLIQ,ILLIQ,test7);
%RegMean(IVOL,IVOL,test8);


/***所有变量数据集汇总，进行回归***/
/*宏5：排序宏*/
%MACRO Sort(InputData);
PROC SORT DATA=&InputData;
  by Year Month PERMNO;
RUN;
%MEND;
%Sort(MAX);
%Sort(Lagged_MAX);
%Sort(Size);
%Sort(BETA);
%Sort(BM);
%Sort(MOM);
%Sort(REV);
%Sort(ILLIQ);
%Sort(IVOL);


/*整合数据*/
DATA MergeData;
  merge MAX(in=a)
        Lagged_MAX(in=b rename=(MAX=MAX_lagged))
        Size(in=c) BETA(in=d) BM(in=e) MOM(in=f) REV(in=g) ILLIQ(in=h) IVOL(in=i);
  by Year Month PERMNO;
RUN;
DATA MergeData;
  set MergeData;
  MktCap = lag(MktCap);
  MktSize = lag(MktSize);
  BETA = lag(BETA);
  BM = lag(BM);
  MOM = lag(MOM);
  REV = lag(REV);
  ILLIQ = lag(ILLIQ);
  IVOL = lag(IVOL);
  if (Year > 1962 or (Year = 1962 and Month >= 7)) and (Year < 2005 or (Year = 2005 and Month <= 12));
  if cmiss(of _all_)=0;
RUN;

/*回归分析*/
/*分析宏*/
%MACRO RegAnalysis(Var,OutputData);
PROC REG DATA=MergeData outest=MergePE1 rsquare noprint;	/*这里采用普通回归，为了得到估计系数与R^2，存储在MergePE1中*/
   by Year Month;
   model MAX = MAX_Lagged MktSize BETA BM MOM REV ILLIQ IVOL;
RUN;

ODS output ParameterEstimates=MergePE2;
PROC AUTOREG DATA=MergePE1;
   model &Var = /covest=neweywest(gamma=0, rate=0, constant=6);	/*这里把Var对常数回归，为了得到Newey-West调整后的t值，一般滞后阶数设为6*/
RUN;
ODS output close;

/*参数平均*/
PROC MEANS DATA = MergePE1 mean noprint;
  var &Var;
  output out=Coef(keep=MeanCoef) mean=MeanCoef;
RUN;
PROC MEANS DATA = MergePE1 mean noprint;
  var _Rsq_;
  output out=Rsquare(keep=MeanRsquare) mean=MeanRsquare;
RUN;
DATA MergePE2;
  set MergePE2;
  keep tvalue;
RUN;

DATA &OutputData;
  merge Coef Rsquare MergePE2;	/*整理过程数据，汇总到OutputData返回*/
RUN;
PROC DATASETS noprint; delete MergePE1 MergePE2 Coef Rsquare; QUIT;	/*删除过程变量，节省空间*/
%MEND;
%RegAnalysis(MAX_Lagged,MAX_Lagged_Coef);
%RegAnalysis(BETA,BETA_Coef);
%RegAnalysis(MktSize,Size_Coef);
%RegAnalysis(BM,BM_Coef);
%RegAnalysis(MOM,MOM_Coef);
%RegAnalysis(REV,REV_Coef);
%RegAnalysis(ILLIQ,ILLIQ_Coef);
%RegAnalysis(IVOL,IVOL_Coef);



/********************************************************************************************************************************************************************
																TABLE5 构造指标变量
********************************************************************************************************************************************************************/
/*制作数据集*/
DATA Crspmonthly;
  set MAX.Crspmonthly;
  Year = year(Date);
  Month = month(Date);
RUN;

DATA MergePortfolio_0;
  merge Crspmonthly(in=a) Lagged_MAX(in=b rename=(MAX=MAX_Lagged)) MAX(in=c) Size(in=d) BETA(in=e) BM(in=f) MOM(in=g) REV(in=h) ILLIQ(in=i) IVOL(in=j);
  by Year Month PERMNO;
RUN;
DATA MergePortfolio_1;
  set MergePortfolio_0;
  keep PERMNO Year Month MAX MAX_Lagged MktCap PRC BETA BM ILLIQ IVOL REV MOM;
  IVOL = IVOL/10;
  MOM = MOM*100;
  if (Year > 1962 or (Year = 1962 and Month >= 7)) and (Year < 2005 or (Year = 2005 and Month <= 12));
RUN;
PROC SORT DATA=MergePortfolio_1;
  by Year Month PERMNO;
RUN;
PROC RANK DATA=MergePortfolio_1 OUT=MergePortfolio_2 groups=10;
  by Year Month;
  var MAX_Lagged;
  ranks Group;
RUN;
/*分组变量的中位数统计*/
PROC SORT DATA=MergePortfolio_2;
  by Year Month Group;
RUN;
PROC MEANS DATA=MergePortfolio_2 noprint;
  by Year Month Group;
  var MAX MktCap PRC BETA BM ILLIQ IVOL REV MOM;
  output out=MergePortfolio_3 median=Med_MAX Med_MktCap Med_PRC Med_Beta Med_BM Med_ILLIQ Med_IVOL Med_REV Med_MOM;
RUN;
/*中位数的平均值统计*/
PROC SORT DATA=MergePortfolio_3;
  by Group;
RUN;
PROC MEANS DATA=MergePortfolio_3 noprint;
  by Group;
  var Med_MAX Med_MktCap Med_PRC Med_Beta Med_BM Med_ILLIQ Med_IVOL Med_REV Med_MOM;
  output out=MergePortfolio_Mean mean=Mean_MAX Mean_MktCap Mean_PRC Mean_Beta Mean_BM Mean_ILLIQ Mean_IVOL Mean_REV Mean_MOM;
RUN;
DATA MergePortfolio_Mean;
  set MergePortfolio_Mean;
  if Group^=.;
PROC DATASETS noprint; delete Crspmonthly MergePortfolio_0 MergePortfolio_1 MergePortfolio_2 MergePortfolio_3 MergePortfolio_Median; RUN;
