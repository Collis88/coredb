--
-- upgradeDB--
--
-- (C)opyright Connect Technology Group 20xx
--
-- Description:
--
-- Database schema changes, patches  to be performed
--
-- Included as part of build process (See proc-enc). This script is followed by the
-- contents of sql/UDFs, sql/views, and sql/procs, and finally by the contents of
-- upgradeDBfinal.sql.
--
-- When executed, all comments / leading spaces are stripped, and the statement to be executed is
-- terminated by "go". Procedures / functions are encrypted and set to execute as dbo.

if object_id('programsettings') is null
begin
  raiserror('Not a ConnectChildcare Database',16,1)
  return
end
go


-- Force compatibility to latest for server ...
declare @dbcompat nvarchar(1000)
select @dbcompat = N'use master
alter database [' + db_name() + '] set compatibility_level = '
+ left(convert(nvarchar,SERVERPROPERTY('ProductVersion')),charindex(N'.',convert(nvarchar,SERVERPROPERTY('ProductVersion'))) - 1)
+ '0'
exec executesql @dbcompat
go



if object_id('upgradeDB') is not null
	drop procedure upgradeDB
go

-- exec upgradeDB
create procedure upgradeDB with encryption as
begin
--  select 'X'

BEGIN TRY

begin transaction

if object_id('programsettings') is null
  raiserror('Not a ConnectChildcare Database',16,1)

if exists (select 1 from programsettings where version < 5506)
  raiserror('Database version must be 5.5.6 or greater',16,1)

-- DB Version 5.5.6 and onwards -

if object_id('childMarkOffNote') is null 
	create table childMarkOffNote ([id] int not null identity(1,1) primary key,
									childID int not null,
									sessionDate date,
									udSesID int not null,
									note varchar(200))

--CC-3059 - Increase the character length of the contacts notes field
alter table contacts alter column notes varchar(5000)

exec executesql N'if not exists (select 1 from Lookup where item = ''DDUse6DayRule'')
	insert into Lookup (item, description, value, ordinal)
	select ''DDUse6DayRule'', ''Use 6 day rule when authorising payers'',1, max(ordinal)+1 from lookup'

--CC-3371
exec executesql N'if not exists (select * from SiteLookup where item = ''BILL-TIMESHEET-AMEND-AFTER-DATE'')

insert into SiteLookup (siteID, item, value, description, ordinal) (
	select s.siteID
	,''BILL-TIMESHEET-AMEND-AFTER-DATE''
	,''''
	,''Format : DD/MM/YYYY : Do not allow modifications to staff assignements/shifts before this date.''
	,max(sl.ordinal)
	from Site s left outer join SiteLookup sl on s.siteID = sl.siteID
	group by s.siteID
)'

exec executesql N'if not exists (select * from lookup where item = ''SITESTAFFING-AUTOREFRESH'') 
INSERT INTO Lookup (item, value, description, ordinal)
(SELECT ''SITESTAFFING-AUTOREFRESH'',1,''0 = Do not auto refresh.  The user will have to manually refresh to see any updates made, 1 = Auto refresh to reflect any changes (default)'',isnull(max(ordinal),1) + 1
FROM lookup)'


exec executesql N'if exists (select 1 from Lookup where item = ''STAFF-ADMIN-USER-LEVEL'')
	update lookup set [description] = ''0 - Only company administrators can see Contract, History, Attendance and Review tabs, as well as staff year view; 1 - Visible to site admin as well, 2 - Company administrators have full access, site administrators only have read only access.'' where item = ''STAFF-ADMIN-USER-LEVEL'''

--CC-3378 Add break entitlement to staff employment history
if not exists (select * from information_schema.columns where table_name = 'StaffEmploymentHistory' and column_name = 'breakEntitlement')
	alter table staffemploymenthistory add breakEntitlement int default 0

if not exists (select * from information_schema.columns where table_name = 'StaffAssign' and column_name = 'breakEntitlement')
	alter table staffassign add breakEntitlement int default 0

--CC-3373 Increase allowed characters in staff member notes column
if exists (select * from information_schema.columns  where table_name = 'StaffMember' and column_name = 'Notes' and character_maximum_length < 8000)
alter table StaffMember alter column notes varchar(8000)

exec executesql N'if not exists (select 1 from Lookup where item = ''EXPORT-NUMBERS-AS'')
	insert into Lookup (item, description, value, ordinal)
	select ''EXPORT-NUMBERS-AS'', ''0 = Export numbers as text, 1 = Export Numbers as numbers'',0, max(ordinal)+1 from lookup'

if not exists(select * from  information_schema.columns where  table_name = 'sessionpattern' and column_name = 'WLDateRequested')
	begin
		alter table sessionpattern add WLDateRequested smalldatetime default '2050-01-01'

		exec('update sessionpattern set WLDateRequested = ''2050-01-01''
		where WLDateRequested is null')
	end

-- CC-3516 - Improvements to Staff Ratio
If exists(select 1 from information_schema.columns where table_name = 'staffprofile' and column_name = 'level3')
	alter table staffprofile drop column level3

If exists(select 1 from information_schema.columns where table_name = 'staffprofile' and column_name = 'level6')
	alter table staffprofile drop column level6

if not exists(select 1 from information_schema.columns where table_name = 'staffprofile' and column_name = 'colour')
	alter table staffprofile add colour varchar(6) not null default 'FFFFFF'

exec executesql N'if not exists (select 1 from Lookup where item = ''HelpdeskURL'')
	insert into Lookup (item, description, value, ordinal)
	select ''HelpdeskURL'', ''The URL of the connect childcare helpdesk'',''https://connectchildcare.zendesk.com/hc/en-gb/sections/360003851593-Preparing-for-your-Connect-Childcare-Upgrade'', max(ordinal)+1 from lookup'

if not exists(select 1 from information_schema.columns where table_name = 'userx' and column_name = 'acceptedDBVersion')
	alter table userx add acceptedDBVersion varchar(15)

if not exists(select 1 from information_schema.columns where table_name = 'userx' and column_name = 'acceptedFEVersion')
	alter table userx add acceptedFEVersion varchar(15)

if not exists(select * from information_schema.columns where table_name = 'StaffEmploymentHistory' and column_name = 'reference1')
	alter table StaffEmploymentHistory add reference1 varchar(255)

if not exists(select * from information_schema.columns where table_name = 'StaffEmploymentHistory' and column_name = 'reference2')
	alter table StaffEmploymentHistory add reference2 varchar(255)

if not exists(select * from ReportUserDefFields where Entity = 'Staff' and Field = 'Reference 1')
	insert into ReportUserDefFields (Entity, Field, Ordinal, MinReadLevel)
	select 'Staff','Reference 1',max(ordinal)+1,1 from ReportUserDefFields where Entity = 'Staff'

if not exists(select * from ReportUserDefFields where Entity = 'Staff' and Field = 'Reference 2')
	insert into ReportUserDefFields (Entity, Field, Ordinal, MinReadLevel)
	select 'Staff','Reference 2',max(ordinal)+1,1 from ReportUserDefFields where Entity = 'Staff'

if not exists(select * from ReportUserDefFields where Entity = 'Staff' and Field = 'Break Entitlement')
	insert into ReportUserDefFields (Entity, Field, Ordinal, MinReadLevel)
	select 'Staff','Break Entitlement',max(ordinal)+1,1 from ReportUserDefFields where Entity = 'Staff'

if not exists(select * from ReportUserDefFields where Entity = 'Staff' and Field = 'Payroll Number')
	insert into ReportUserDefFields (Entity, Field, Ordinal, MinReadLevel)
	select 'Staff','Payroll Number',max(ordinal)+1,1 from ReportUserDefFields where Entity = 'Staff'
--

--CC-3566 - Remove existing default on userdefined/defaultExtra column and add a new one 'default 1'

declare @defaultName varchar(max)
select @defaultName = default_constraints.name from sys.all_columns
	inner join sys.tables ON all_columns.object_id = tables.object_id
	inner join sys.schemas ON tables.schema_id = schemas.schema_id
	inner join sys.default_constraints ON all_columns.default_object_id = default_constraints.object_id
	where schemas.name = 'dbo' AND tables.name = 'userdefined' AND all_columns.name = 'defaultextra' AND definition = '((2))'

if @defaultName is not null
begin
	exec('alter table userdefined drop constraint '+@defaultName+' ;'+
		 'alter table userdefined add constraint userdefined_defaultExtra_constraint default 1 for defaultextra'
		)
end

-- CC-3703 - Allow Happy Days to override BILL-CM-WEEKLY-CHANGED-FLAG per billing run

exec executesql N'if not exists (select 1 from Lookup where item = ''GLOBAL-CM-WEEKLY-CHANGED-OPTION'')
	insert into Lookup (item, description, value, ordinal)
	select ''GLOBAL-CM-WEEKLY-CHANGED-OPTION'', ''0 = no billing run option 1 = billing run option available'',0, max(ordinal)+1 from lookup'

-- CC3796 - Add logging to the comms area
if object_id('TraceLog') is null
	create table TraceLog(
	[id] int identity Primary Key,
	[Date] datetime,
	[UserID] int,
	[Notes] varchar(max))

if not exists (select * from Lookup where item = 'ENABLE-TRACE-LOG')
 insert into Lookup (item, description, value, ordinal)
	select 'ENABLE-TRACE-LOG', 'Enable trace logging 0 = do not add trace log entries (defaultValue), 1 = add trace log entries',0, max(ordinal)+1 from lookup

if not exists(select ID from Lookup where item = 'REPORTTIMEOUTSECS')
  insert into Lookup(item,value,description,ordinal) 
  select 'REPORTTIMEOUTSECS','120','Report timeout in seconds',max(ordinal)+ 1 from lookup

if not exists(select * from information_schema.columns where table_name = 'Site' and column_name = 'siteCode')
	alter table site add siteCode varchar(10)

if object_id('SiteCodeFields') is null
begin
	create table SiteCodeFields (
	[id] int identity not null primary key,
	[fieldName] varchar(50) not null,
	[ordinal] smallint)

	insert into SiteCodeFields values ('Bill Payer Ref',1)
end

IF OBJECT_ID('PayPoint') is null
BEGIN
	CREATE TABLE PayTableStatus(
	[id] TINYINT NOT NULL IDENTITY PRIMARY KEY,
	[description] VARCHAR(50),
	[ordinal] SMALLINT
	)

	INSERT INTO PayTableStatus VALUES ('Active',1),('Future',2),('Expired',3)

	CREATE TABLE PayTable(
	[id] SMALLINT NOT NULL IDENTITY PRIMARY KEY,
	[contractTypeID] INTEGER FOREIGN KEY REFERENCES ContractType(id),
	[statusID] TINYINT FOREIGN KEY REFERENCES PayTableStatus(id),
	[reference] VARCHAR(8),
	[dFrom] DATE,
	[dTo] DATE,
	[createdOn] DATETIME,
	[createdBy] INT)

	CREATE TABLE PayTableSites(
	[id] SMALLINT NOT NULL IDENTITY PRIMARY KEY,
	[payTableID] SMALLINT FOREIGN KEY REFERENCES PayTable(id),
	[siteID] INT)

	CREATE TABLE PayTableSiteGroups(
	[id] SMALLINT NOT NULL IDENTITY PRIMARY KEY,
	[payTableID] SMALLINT FOREIGN KEY REFERENCES PayTable(id),
	[siteGroupID] INT)

	CREATE TABLE PayPoint (
	[id] SMALLINT NOT NULL IDENTITY PRIMARY KEY,
	[payTableID] SMALLINT NOT NULL FOREIGN KEY REFERENCES PayTable(id),
	[payPoint] TINYINT,
	[salary] DECIMAL(8,2),
	)

	CREATE TABLE PayRates(
	[id] SMALLINT NOT NULL IDENTITY PRIMARY KEY,
	[rate] TINYINT,
	[description] VARCHAR(100),
	[ordinal] SMALLINT
	)

	INSERT INTO PayRates ([rate], [description], [ordinal])
	VALUES (2, 'Standard Hourly Rate',1)

	CREATE TABLE PayPointRates(
	[id] SMALLINT NOT NULL IDENTITY PRIMARY KEY,
	[payPointID] SMALLINT FOREIGN KEY REFERENCES PayPoint(id),
	[rateID] SMALLINT FOREIGN KEY REFERENCES PayRates(id),
	[value] decimal(4,2))
END

if not exists (select * from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = 'StaffEmploymentHistory' and COLUMN_NAME = 'paypoint')
	alter table staffEmploymentHistory add paypoint smallint

if not exists(select * from ReportUserDefFields where Entity = 'Staff' and Field = 'Pay Point')
	insert into ReportUserDefFields (Entity, Field, Ordinal, MinReadLevel)
	select 'Staff','Pay Point',max(ordinal)+1,1 from ReportUserDefFields where Entity = 'Staff'

if not exists(select ID from lookup where item = 'SALARYMANAGEMENT')
	insert into Lookup(item,description,value, ordinal)
	values ('SALARYMANAGEMENT','This controls whether the salary management features are enabled.  1 = Enabled, 0 = Disabled (Default)',0,0)

if not exists(select * from lookup where item = 'STAFFPLAN')
	begin
		insert into Lookup(item,description,value, ordinal)
		values ('STAFFPLAN','This controls whether the staffplan features are enabled.  1 = Enabled, 0 = Disabled (Default)',0,0)

		declare @value varchar(4000)

		select @value = isnull(convert(varchar(4000),DecryptByPassPhrase(
		concat(isnull(convert(varchar(max),SERVERPROPERTY('MachineName')),''),'|',convert(varchar,SERVERPROPERTY('ServerName')),'#',db_name(),'^','STAFF-PLANNER-LIC')
		, convert(varbinary(max),value,2) )),value)
		from Lookup where ordinal = 0 and item = 'STAFF-PLANNER-LIC'

		set @value = substring(@value,1,len(@value) - 8)

		--Enable the flag for any customer that currently has a license
		if isnumeric(@value) = 1 and @value > 0
			update lookup set value = 1 where item = 'STAFFPLAN'
	
		delete from lookup where item = 'STAFF-PLANNER-LIC'
	end

if not exists (select * from lookup where item = 'LIC-PEAK-OCCUPANCY')
begin
	insert into Lookup(item,description,value, ordinal)	values ('LIC-PEAK-OCCUPANCY','Peak Occupancy',0,0)

	declare @licpeak varchar(4000)

	select @licpeak = isnull(convert(varchar(4000),DecryptByPassPhrase(
	concat(isnull(convert(varchar(max),SERVERPROPERTY('MachineName')),''),'|',convert(varchar,SERVERPROPERTY('ServerName')),'#',db_name(),'^','PEAK-OCCUPANCY-LIC')
	, convert(varbinary(max),value,2) )),value)
	from Lookup where ordinal = 0 and item = 'PEAK-OCCUPANCY-LIC'

	set @licpeak = substring(@licpeak,1,len(@licpeak) - 8)

	--Enable the flag for any customer that currently has a license
	if isnumeric(@licpeak) = 1 and @licpeak > 0

		update lookup set value = @licpeak where item = 'LIC-PEAK-OCCUPANCY'
	
	delete from lookup where item = 'PEAK-OCCUPANCY-LIC'

end

if not exists (select * from lookup where item = 'LIC-SITE')
begin
	insert into Lookup(item,description,value, ordinal)	values ('LIC-SITE','No. Sites',0,0)

		declare @licsites varchar(4000)

	select @licsites = isnull(convert(varchar(4000),DecryptByPassPhrase(
	concat(isnull(convert(varchar(max),SERVERPROPERTY('MachineName')),''),'|',convert(varchar,SERVERPROPERTY('ServerName')),'#',db_name(),'^','SITE-LIC')
	, convert(varbinary(max),value,2) )),value)
	from Lookup where ordinal = 0 and item = 'SITE-LIC'

	set @licsites = substring(@licsites,1,len(@licsites) - 8)

	--Enable the flag for any customer that currently has a license
	if isnumeric(@licsites) = 1 and @licsites > 0

		update lookup set value = @licsites where item = 'LIC-SITE'
	
	delete from lookup where item = 'SITE-LIC'

end

if not exists (select * from lookup where item = 'LIC-STAFF-WAGES')
begin
	insert into Lookup(item,description,value, ordinal)	values ('LIC-STAFF-WAGES','Staff Wages module',0,0)

		declare @licwages varchar(4000)

	select @licwages = isnull(convert(varchar(4000),DecryptByPassPhrase(
	concat(isnull(convert(varchar(max),SERVERPROPERTY('MachineName')),''),'|',convert(varchar,SERVERPROPERTY('ServerName')),'#',db_name(),'^','STAFF-WAGES-LIC')
	, convert(varbinary(max),value,2) )),value)
	from Lookup where ordinal = 0 and item = 'STAFF-WAGES-LIC'

	set @licwages = substring(@licwages,1,len(@licwages) - 8)

	--Enable the flag for any customer that currently has a license
	if isnumeric(@licwages) = 1 and @licwages > 0

		update lookup set value = @licwages where item = 'LIC-STAFF-WAGES'
	
	delete from lookup where item = 'STAFF-WAGES-LIC'

end

if not exists (select * from lookup where item = 'LIC-WS')
begin
	insert into Lookup(item,description,value, ordinal)	values ('LIC-WS','No. workstations',0,0)

		declare @licws varchar(4000)

	select @licws = isnull(convert(varchar(4000),DecryptByPassPhrase(
	concat(isnull(convert(varchar(max),SERVERPROPERTY('MachineName')),''),'|',convert(varchar,SERVERPROPERTY('ServerName')),'#',db_name(),'^','WS-LIC')
	, convert(varbinary(max),value,2) )),value)
	from Lookup where ordinal = 0 and item = 'WS-LIC'

	set @licws = substring(@licws,1,len(@licws) - 8)

	--Enable the flag for any customer that currently has a license
	if isnumeric(@licws) = 1 and @licws > 0

		update lookup set value = @licws where item = 'LIC-WS'
	
	delete from lookup where item = 'WS-LIC'

end

if not exists (select * from lookup where item = 'LIC-XERO-INTEGRATION')
begin
	insert into Lookup(item,description,value, ordinal)	values ('LIC-XERO-INTEGRATION','Xero Accounts integration',0,0)

		declare @licxero varchar(4000)

	select @licxero = isnull(convert(varchar(4000),DecryptByPassPhrase(
	concat(isnull(convert(varchar(max),SERVERPROPERTY('MachineName')),''),'|',convert(varchar,SERVERPROPERTY('ServerName')),'#',db_name(),'^','XERO-INTEGRATION-LIC')
	, convert(varbinary(max),value,2) )),value)
	from Lookup where ordinal = 0 and item = 'XERO-INTEGRATION-LIC'

	set @licxero = substring(@licxero,1,len(@licxero) - 8)

	--Enable the flag for any customer that currently has a license
	if isnumeric(@licxero) = 1 and @licxero > 0

		update lookup set value = @licxero where item = 'LIC-XERO-INTEGRATION'
	
	delete from lookup where item = 'XERO-INTEGRATION-LIC'

end

	 
	

if not exists(select * from information_schema.columns where table_name = 'StaffAssignStatus' and column_name = 'exceptionType')
	alter table staffAssignStatus add exceptionType varchar(9) constraint chk_staffassignexception check (exceptionType in ('','Addition','Deduction') or exceptionType is null)

if not exists(select * from information_schema.columns where table_name = 'StaffAssignStatus' and column_name = 'reference')
	alter table staffAssignStatus add reference varchar(10)


if not exists (select * from reportV3 where reportName = 'Payroll Exports')
begin
	insert into ReportV3 (reportID, reportName, storedProcedure, sectionID, variables,version)
	values (420, 'Payroll Exports','rpt_UserDefinedPayrollExportDetails',13,'cmb1,Site,REPORT_GetSiteAndSiteGroupComboWithAll,dtm1,Date From,dtm2,Date To,cmb2,Report Format,REPORT_GetUDPayrollExportDetailsReportFormat',5002)

	insert into ReportUserDefEntities (ReportName, Entity, ordinal)
	values ('Payroll Exports','blank',0)
	      ,('Payroll Exports','Staff',1)
	      ,('Payroll Exports','Payroll',2)

	insert into ReportUserDefFields(Entity, Field, ordinal,minReadLevel)
	values ('Payroll','Total Hours Worked',1,1)
		  ,('Payroll','Exception Hours',2,1)
		  ,('Payroll','Hourly Rate',3,1)
		  ,('Payroll','Salaried',4,0)
		  ,('Payroll','Salary',5,1)
		  ,('Payroll','Monthly Salary',6,1)
		  ,('Payroll','Hours',7,1)
		  ,('Payroll','Payment Reference',8,1)
		  ,('Payroll','Employee Reference',9,1)
		  ,('Payroll','Date From',10,1)
		  ,('Payroll','Date To',11,1)

	insert into ReportUserDefs (ReportName,ReportFormat,Entity,Field, Alias, FilterBy, Ordinal)
	values ('Payroll Exports','Default','Staff','Staff Ref','Staff Ref',null,1)
          ,('Payroll Exports','Default','Payroll','Payment Reference','Payment Reference',null,2)
		  ,('Payroll Exports','Default','Payroll','Hours','Hours',null,3)
		  ,('Payroll Exports','Default','Payroll','Date From','Date From',null,4)
		  ,('Payroll Exports','Default','Payroll','Date To','Date To',null,5)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Payroll Number','Employee Reference',null,6)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Payment Reference','Payment Reference',null,7)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Exception Hours','Hours',null,8)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Hourly Rate','Rate',null,9)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Monthly Salary','Salary',null,10)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Salaried','Salaried','Y',11)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Date From','Date From',null,12)
		  ,('Payroll Exports','Salaried Payroll Export','Payroll','Date To','Date To',null,13)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Payroll Number','Employee Reference',null,14)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Payment Reference','Payment Reference',null,15)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Total Hours Worked','Hours',null,16)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Hourly Rate','Hourly Rate',null,17)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Salaried','Salaried','N',18)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Date From','Date From',null,19)
		  ,('Payroll Exports','Bank Payroll Export','Payroll','Date To','Date To',null,20)
		  
end

if not exists (select * from information_schema.columns where table_name = 'ContractType' and column_name = 'Salaried')
begin
	alter table ContractType add Salaried char(1) default 'Y'
	exec executesql N'update ContractType set Salaried = ''Y'''
end

If not exists(select 1 from attlist where name = 'EYFS Qualification')
begin
	declare @attlistID int
	insert into attlist (name, type) values ('EYFS Qualification','Combo')
		select @attlistID = SCOPE_IDENTITY()

	insert into att (name,dFromLabel,dToLabel,valLabel,minDate,maxDate,minInt,maxInt,minDbl,maxDbl
		,minLen,maxLen,bMergeStrings,minReadLevel,minWriteLevel,minAuthLevel,attListID,maxCount,displayAsHistory
		,reminderFlags,reminderCount,reminderDays,deleted,wide,valIsDate,allowSearch)
	values
		('EYFS Relevant Qualification','Valid From','',NULL,'1970-01-01',NULL,-2147483648,-2147483648,NULL,NULL
			,0,2000,0,1,1,0,@attListID,NULL,1,2,2,28,0,1,0,0)

	declare @attID int
	select @attID = SCOPE_IDENTITY() 
	
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'GCSE Maths',15,2)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'GCSE English',16,3)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'GCSE ICT',17,4)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID, 'GCSE Science',18,5)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Functional Skills Maths English ICT Level 1',19,6)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Functional Skills Maths English ICT Level 2',20,7)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Children and Young Peoples Workforce Level 2',21,8)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID, 'Early Years Practitioner Level 2',22,9)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Early Years Educator Level 3',23,10)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'NNEB',	24,	11)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'NNED',	25,	12)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Childrens Care Learning and Development Level 3',26,13)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Childcare and Education Level 2',27,14)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Childcare and Education Level 3',28,15)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Playwork Level 2',29,16)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Playwork Level 3',30,17)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Playwork Level 4',31,18)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'STLS Level 2',32,19)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'STLS Level 3',33,20)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'STLS Level 4',34,21)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Foundation degree Early Years/Childcare (check full and relevant)',35,22)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Degree Early Years/Childcare (check full and relevant)',36,23)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Early Years Professional',37,24)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Early Years Teacher',38,25)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'QTLS',39,26)
	insert into attlistValue (attlistID, item, value, ordinal)
		values (@attlistID,	'Masters degree',40,27)
	
	declare @attGroupID int
	select @attGroupID = id from attgroup 
		where description = 'Qualifications' and appliesTo = 'Staff'
			
	insert into AttGroupAtt
		select @attGroupID, @attID, max(ordinal), 0  from attgroupatt
			where attGroupID = @attGroupID

	insert into StaffProfileAtt (spID, attID, bMandatory, ordinal)
		select distinct sp.ID, @attID, 0, 1
			from staffprofile sp
			left join StaffProfileAtt spa on sp.ID = spa.spID and attID = @attID
			where spa.id is null
end

-- Add Lookup Items for Interest Rate Adjustments
exec executesql N'if not exists(select 1 from lookup where item = ''BILL-INTEREST-RATE-PERCENTAGE'')
	insert into lookup (item,value,description,ordinal) 
	select ''BILL-INTEREST-RATE-PERCENTAGE'',''0.00'',''If a rate is set (to 2 decimal places), an adjustment line item will be created on bills with this % of the Billpayers outstanding balance as at the bill date.'',max(ordinal)+1 from lookup'

exec executesql N'if not exists(select 1 from lookup where item = ''BILL-INTEREST-RATE-TRANSACTION-CODE'')
	insert into lookup (item,value,description,ordinal) 
	select ''BILL-INTEREST-RATE-TRANSACTION-CODE'','''',''The Transaction Code to be used in Accounts Exports for the Interest Rate Adjusment type line items.'',max(ordinal)+1 from lookup'

exec executesql N'if not exists(select 1 from lookup where item = ''BILL-INTEREST-RATE-EXTERNAL-REFERENCE'')
	insert into lookup (item,value,description,ordinal) 
	select ''BILL-INTEREST-RATE-EXTERNAL-REFERENCE'','''',''The External Reference to be used in Accounts Exports for the Interest Rate Adjusment type line items.'',max(ordinal)+1 from lookup'

	
-- Propagate billing Lookup items to the SiteLookup table where they don't already exist.
exec executesql N'insert SiteLookup(siteID,item,value,description,ordinal)
select s.siteID,l.item,l.value,l.description,l.ordinal
from Lookup l
join Site s on l.item like ''BILL-%'' or l.item in (''Staff Holiday Year Start'')
left join SiteLookup sl on sl.siteID = s.siteID and sl.item = l.item
where sl.siteID is null'


--CC-3834 - alter table userx
If not exists(select 1 from INFORMATION_SCHEMA.columns where table_name = 'UserX' and COLUMN_NAME = 'complexPW')
begin
	exec executesql N'alter table UserX add complexPW bit null default 0'
	exec executesql N'update UserX set complexPW = 0'
end

--CC-3834 - UserXPassHistory Table
if not exists(select 1 from INFORMATION_SCHEMA.tables where TABLE_NAME = 'UserXPassHistory')
begin
	create table [dbo].[UserXPassHistory](
		[ID] [bigint] identity(1,1) NOT NULL,
		[userID] [int] NOT NULL,
		[login] [varchar](30) NULL,
		[pass] [varchar](32) NULL,
		[dt_created] [datetime] NULL default GETDATE()
	) on [PRIMARY]
end

--CC-3834 - add any current passwords into the history log
 exec executesql N'insert into UserXPassHistory([userID],[login],[pass],[dt_created])
		         select u.[userID],u.[login],u.[pass],GETDATE() from userx u 
				 left join UserXPassHistory uh on u.userID = uh.userID and u.pass = uh.pass where uh.userID is null'


--CC-3834 - passSettings Table
if not exists(select 1 from INFORMATION_SCHEMA.tables where TABLE_NAME = 'passSettings')
begin
	create table [dbo].[passSettings](
	    [ID] [bigint] IDENTITY(1,1) NOT NULL,
		[minimum] [smallint] NOT NULL default 8,
		[special] [bit] NOT NULL default 0,
		[upperLower] [bit] NOT NULL default 0,
		[number] [bit] NOT NULL default 0,
		[reusePrevious] [bit] NOT NULL default 0,
		[retryAttempt] [smallint] NOT NULL default 5,
		[lockoutMinutes] [smallint] NOT NULL default 30,
		[indefiniteLockout] [bit] NOT NULL default 0,
		[CanReusePreviousPassword] [bit] NOT NULL default 1,
		[dt_updated] [datetime] NULL default GETDATE()
	) on [PRIMARY]
end

--CC-3834 - add password settings
 exec executesql N'if not exists (select 1 from passSettings)
	insert into passSettings (minimum,special,upperLower,number,reusePrevious,retryAttempt,lockoutMinutes,indefiniteLockout,CanReusePreviousPassword,dt_updated)
	values (8,0,0,0,0,5,30,0,0,GETDATE())'

--CC-3834 - UserXLoginFail Table
if not exists(select 1 from INFORMATION_SCHEMA.tables where TABLE_NAME = 'UserXLoginFail')
begin
	create table [dbo].[UserXLoginFail](
		[ID] [bigint] identity(1,1) NOT NULL,
		[userID] [int] NOT NULL,
		[login] [varchar](30) NULL,
		[dt_created] [datetime] NULL default GETDATE()
	) on [PRIMARY]
end

--CC-3834 - UserXLocked Table
if not exists(select 1 from INFORMATION_SCHEMA.tables where TABLE_NAME = 'UserXLocked')
begin
	create table [dbo].[UserXLocked](
		[ID] [bigint] identity(1,1) NOT NULL,
		[userID] [int] NOT NULL,
		[login] [varchar](30) NULL,
		[dt_locked] [smalldatetime] NULL default GETDATE(),
		[dt_created] [datetime] NULL default GETDATE()
	) on [PRIMARY]
end

-- CC-4058 - Allow Access to Direct Debit Details permission
If not exists(select 1 from INFORMATION_SCHEMA.columns where table_name = 'UserX' and COLUMN_NAME = 'AllowDDAccess')
begin
	exec executesql N'alter table userx add AllowDDAccess bit not null default 1'
end

-- CC-4217 - Auto-generate staff payroll number
exec executesql N'if not exists(select 1 from lookup where item = ''STAFF-AUTO-GENERATE-PAYROLL-NUMBER'')
	insert into lookup (item,value,description,ordinal) 
	select ''STAFF-AUTO-GENERATE-PAYROLL-NUMBER'',''0'',''0 - Allow user to enter their own Payroll Number in Staff Contracts 1 - Auto generate the Payroll Number from an increment of the current highest one, and dis-allow manual '',max(ordinal)+1 from lookup'

If not exists(select 1 from INFORMATION_SCHEMA.columns where table_name = 'staffEmploymentHistory' and COLUMN_NAME = 'payTableID')
begin
	exec executesql N'alter table staffEmploymentHistory add paytableID int null'
end

if object_id('StaffShiftSets') is null
begin
	create table StaffShiftSets (
	[id] int identity not null primary key,
	[Shift Set Name] varchar(50) not null default '',
	[Shift Length] float not null default 0.00,
	[Payroll Value] float not null default 0.00,
	[ordinal] smallint)
	
	exec executesql 'insert into staffshiftsets ([Shift Set Name],ordinal) values (''New Shift'',1)'
end

If not exists(select 1 from INFORMATION_SCHEMA.columns where table_name = 'staffAssign' and COLUMN_NAME = 'shiftSetID')
begin
	exec executesql N'alter table staffassign add shiftSetID int null'
end

-- CC-4435 -- Add Lookup for use credit date
exec executesql N'
if not exists(select 1 from lookup where item = ''InvoiceUseCreditDate'')
	insert into lookup (item,value,description,ordinal) 
	select ''InvoiceUseCreditDate'',''1'',''0 = default/uses invoice date, 1 = Will use the credit note date for the rpt_InvoiceDetailExport, this means credits raised in a different date filter will not appear in the export. '',max(ordinal)+1 from lookup'
	
exec executesql N'
if not exists(select 1 from lookup where item = ''InvoiceHideRebilledCredits'')
	insert into lookup (item,value,description,ordinal) 
	select ''InvoiceHideRebilledCredits'',''1'',''0 = default, 1 = Exclude credit note rebilled credits from the rpt_InvoiceDetailExport export. '',max(ordinal)+1 from lookup'

if not exists(select * from site where siteName like 'Happy Days%') -- The grant LEA reports are export only so there is no typedata to remove.
	begin
		if exists (select * from reportV3 where reportName = 'Grant LEA Snapshot Detailed')
			delete from reportV3 where reportName = 'Grant LEA Snapshot Detailed'
		if exists (select * from reportV3 where reportName = 'Grant LEA Snapshot Preview')
			delete from reportV3 where reportName = 'Grant LEA Snapshot Preview'
		if exists (select * from reportV3 where reportName = 'Grant LEA All Snapshots')
			delete from reportV3 where reportName = 'Grant LEA All Snapshots'
		if exists (select * from reportV3 where reportName = 'Grant LEA Gross Income Per Year')
			delete from reportV3 where reportName = 'Grant LEA Gross Income Per Year'
	end


-- Set Table Permissions for Direct SQL 
exec executesql N'GRANT EXECUTE ON SCHEMA::[dbo] TO [connectchildcareuser]
GRANT SELECT,UPDATE,INSERT,DELETE ON [dbo].[SiteCodeFields] TO [connectchildcareuser] 
GRANT SELECT,UPDATE,INSERT,DELETE ON [dbo].[StaffShiftSets] TO [connectchildcareuser]
GRANT SELECT,UPDATE,INSERT,DELETE ON [dbo].[PayRates] TO [connectchildcareuser]
GRANT SELECT,UPDATE,INSERT,DELETE ON [dbo].[PayTableStatus] TO [connectchildcareuser]
'

-- Preserve modified itemData templates ...
if object_id('upgTypeData') is not null
    exec executesql N'drop table upgTypeData'
create table upgTypeData(type varchar(50),item varchar(200),id int)
	exec executesql N'insert upgTypeData select type,item,id from typeData where active = 1 and Notes <> '''''


-- Set version number
exec executesql N'update programsettings set version=8340'
declare @dbver varchar(10) = '8.3.4'
declare @dbdesc varchar(200) = '8.3.4 14th Sep 2020'


if not exists (select 1 from Lookup where item = 'DBVERSION') insert Lookup(item,value,description,ordinal) values ('DBVERSION','','',0)
update Lookup set value = @dbver,description = @dbdesc where item = 'DBVERSION'

END TRY

BEGIN CATCH
  rollback transaction
  select ERROR_MESSAGE()
  return
END CATCH

commit transaction

end -- exec upgradeDb

go

exec upgradeDB

if not exists (select * from information_schema.tables where table_name = 'programSettings') RAISERROR ('Error upgrading DB!', 20, 1) with log

if not exists (select 1 from programSettings where version=8340) RAISERROR ('Error upgrading DB!', 20, 1) with log
